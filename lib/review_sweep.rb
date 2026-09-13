# frozen_string_literal: true

require "digest"
require "json"
require "time"

# The pure half of bin/sweep-pr: turns GitHub's review, comment and check-run
# payloads for one pull request into a single normalized picture of its bot
# reviews, and reads and writes the "review sweep" ledger comment. No network
# and no Rails here, so test/lib/review_sweep_test.rb can pin the fragile parts
# (the Copilot and Codex markdown formats) with fixture strings.
module ReviewSweep
  COPILOT_REVIEWER = "copilot-pull-request-reviewer[bot]"
  COPILOT_COMMENTER = "Copilot"
  COPILOT_CHECK_RUN = "copilot-pull-request-reviewer"
  CODEX = "chatgpt-codex-connector[bot]"
  CODEQL = "github-advanced-security[bot]"
  CODEX_SUMMARY_MARKER = "<!-- codex-pull-request-review-summary -->"
  LEDGER_MARKER = "<!-- sweep-ledger -->"
  MAX_ROUNDS = 2
  REQUEST_TIMEOUT = 15 * 60
  STATUSES = %w[open accepted fixed rejected duplicate deferred].freeze
  TERMINAL_STATUSES = %w[fixed rejected duplicate deferred].freeze
  FINDING_FIELDS = %w[id reviewer source sha path line severity title url comment_id].freeze
  CODEX_BADGE = /\A\*\*<sub><sub>!\[(P\d) Badge\][^\n]*?<\/sub><\/sub>\s*(.+?)\*\*[ \t]*$/

  class FormatError < StandardError; end

  module_function

  # ---- Copilot -------------------------------------------------------------

  # Copilot's review submission carries its low-confidence findings only in the
  # body, as "suppressed comments"; nothing else on the PR mentions them. The
  # declared count is checked against what was parsed so a format change fails
  # loudly instead of quietly dropping findings.
  def parse_copilot_review(body)
    headline = body[/^### (.+)$/, 1].to_s.strip
    declared = body[/^### Suppressed comments \((\d+)\)/, 1]
    if declared.nil? && body.match?(/^### Suppressed comments/)
      raise FormatError, "Copilot review has a suppressed-comments heading without a count that parses; " \
                         "the review format may have changed (see lib/review_sweep.rb)"
    end
    generated = body[/^- \*\*Comments generated:\*\* (\d+)/, 1]
    suppressed = declared ? parse_suppressed(body) : []
    if declared && suppressed.size != declared.to_i
      raise FormatError, "Copilot review declares #{declared} suppressed comments but #{suppressed.size} parsed; " \
                         "the review format may have changed (see lib/review_sweep.rb)"
    end
    { "headline" => headline, "suppressed" => suppressed, "generated" => generated&.to_i }
  end

  def parse_suppressed(body)
    section = body.split(/^### Suppressed comments \(\d+\)[ \t]*\n/, 2).last.to_s
    section = section.split(/^(?:- \*\*Files reviewed|<\/details>)/, 2).first.to_s
    items = []
    in_fence = false
    section.each_line(chomp: true) do |line|
      if line.start_with?("```")
        in_fence = !in_fence
      elsif in_fence
        next
      elsif (match = line.match(/\A\*\*(.+):(\d+)\*\*[ \t]*\z/))
        items << { "path" => match[1], "line" => match[2].to_i, "body" => +"" }
      elsif items.any? && items.last["body"].empty?
        items.last["body"] << line.delete_prefix("* ").strip if line.start_with?("* ")
      elsif items.any? && !line.strip.empty? && !line.start_with?("* ")
        items.last["body"] << " " << line.strip
      end
    end
    items
  end

  # ---- Codex ---------------------------------------------------------------

  def parse_codex_comment(body)
    match = body.match(CODEX_BADGE)
    text = (match ? body.sub(match[0], "") : body).strip
    text = text.sub(/\n*Useful\? React with.*\z/m, "").strip
    { "severity" => match && match[1], "title" => match ? match[2].strip : first_sentence(text), "body" => text }
  end

  def codex_reviewed_sha(body)
    body.to_s[/\*\*Reviewed commit:\*\*\s*`([0-9a-f]{7,40})`/, 1]
  end

  def codex_clean?(body)
    body.to_s.include?("Didn't find any major issues")
  end

  def codex_request?(body)
    body.to_s.strip.match?(/\A@codex review\z/i)
  end

  # ---- Assembly ------------------------------------------------------------

  # pull_request is `gh pr view --json` output; the three lists are the raw REST payloads
  # (every page); check_runs are the head commit's runs named COPILOT_CHECK_RUN;
  # ledger is the parsed ledger comment, or {} when none exists yet.
  def assemble(pull_request, reviews, review_comments, issue_comments, check_runs: [], ledger: {}, now: Time.now.utc)
    head = pull_request.fetch("headRefOid")
    head7 = head[0, 7]
    warnings = []
    reviews_by_id = reviews.to_h { |review| [ review["id"], review ] }
    top_level, replies = review_comments.partition { |comment| comment["in_reply_to_id"].nil? }
    replies_by_parent = replies.group_by { |comment| comment["in_reply_to_id"] }

    copilot_reviews = reviews.select { |review| login(review) == COPILOT_REVIEWER }.sort_by { |review| review["submitted_at"] }
    round_heads = copilot_reviews.map { |review| review["commit_id"] }.uniq # full SHAs: prefixes can collide
    rounds = round_heads.map { |sha| sha[0, 7] }

    findings = []
    copilot_reviews.each do |review|
      parsed = parse_copilot_review(review["body"].to_s)
      inline_count = top_level.count { |comment| comment["pull_request_review_id"] == review["id"] && login(comment) == COPILOT_COMMENTER }
      if parsed["generated"] && parsed["generated"] != inline_count
        warnings << "Copilot review #{review["id"]} says it generated #{parsed["generated"]} comments but #{inline_count} are present"
      end
      parsed["suppressed"].each do |item|
        finding = {
          "id" => suppressed_id(item["path"], item["body"]), "reviewer" => "copilot", "source" => "suppressed",
          "sha" => review["commit_id"][0, 7], "path" => item["path"], "line" => item["line"], "outdated" => false,
          "severity" => nil, "title" => first_sentence(item["body"]), "body" => item["body"],
          "url" => review["html_url"], "comment_id" => nil, "replies" => []
        }
        findings.reject! { |existing| existing["id"] == finding["id"] } # the latest sighting wins
        findings << finding
      end
    end

    top_level.sort_by { |comment| comment["created_at"].to_s }.each do |comment|
      reviewer = { COPILOT_COMMENTER => "copilot", CODEX => "codex", CODEQL => "codeql" }[login(comment)]
      next unless reviewer
      sha = reviews_by_id.dig(comment["pull_request_review_id"], "commit_id") || comment["original_commit_id"]
      parsed = case reviewer
      when "codex" then parse_codex_comment(comment["body"].to_s)
      when "codeql" then { "severity" => nil, "title" => comment["body"].to_s[/\A## (.+)$/, 1].to_s.strip, "body" => comment["body"].to_s.strip }
      else { "severity" => nil, "title" => first_sentence(comment["body"].to_s), "body" => comment["body"].to_s.strip }
      end
      findings << parsed.merge(
        "id" => "#{reviewer}:#{comment["id"]}", "reviewer" => reviewer, "source" => "inline", "sha" => sha.to_s[0, 7],
        "path" => comment["path"], "line" => comment["line"] || comment["original_line"], "outdated" => comment["line"].nil?,
        "url" => comment["html_url"], "comment_id" => comment["id"],
        "replies" => (replies_by_parent[comment["id"]] || []).map do |reply|
          { "author" => login(reply), "created_at" => reply["created_at"], "excerpt" => reply["body"].to_s.strip[0, 200] }
        end
      )
    end

    # A ledger status counts only when the entry justifies it, and a finding
    # marked fixed that Copilot raises again on a later head is open again.
    ledger_entries = Array(ledger["findings"]).to_h { |entry| [ entry["id"], entry ] }
    findings.each do |finding|
      entry = ledger_entries[finding["id"]]
      finding["ledger_status"] = if entry.nil?
        "open"
      elsif (problem = entry_problem(entry, ledger_entries.keys))
        warnings << "ledger entry #{finding["id"]}: #{problem}; treated as open"
        "open"
      elsif resurfaced?(entry, finding)
        warnings << "#{finding["id"]} resurfaced at #{finding["sha"]} after being fixed in #{entry["fixed_in"]}; treated as open"
        "open"
      else
        entry["status"]
      end
    end

    copilot_head_review = copilot_reviews.reverse.find { |review| review["commit_id"] == head }
    copilot_running = check_runs.any? { |run| run["name"] == COPILOT_CHECK_RUN && run["status"] != "completed" }
    copilot_requested = Array(pull_request["reviewRequests"]).any? { |request| request.to_json.match?(/copilot/i) }
    copilot = {
      "sha" => copilot_reviews.last&.dig("commit_id")&.slice(0, 7),
      "review_id" => copilot_head_review&.dig("id"),
      "headline" => copilot_head_review && parse_copilot_review(copilot_head_review["body"].to_s)["headline"],
      "inline" => findings.count { |finding| finding["reviewer"] == "copilot" && finding["source"] == "inline" && finding["sha"] == head7 },
      "suppressed" => findings.count { |finding| finding["reviewer"] == "copilot" && finding["source"] == "suppressed" && finding["sha"] == head7 },
      "done_for_head" => !copilot_head_review.nil?,
      "pending" => copilot_requested || copilot_running
    }

    codex_outputs = reviews.select { |review| login(review) == CODEX }.map do |review|
      { "sha" => review["commit_id"], "at" => review["submitted_at"], "verdict" => "findings" }
    end
    issue_comments.each do |comment|
      next unless login(comment) == CODEX && !comment["body"].to_s.include?(CODEX_SUMMARY_MARKER)
      sha = codex_reviewed_sha(comment["body"]) or next
      codex_outputs << { "sha" => sha, "at" => comment["created_at"], "verdict" => codex_clean?(comment["body"]) ? "clean" : "findings" }
    end
    codex_outputs.sort_by! { |output| output["at"].to_s }
    codex_head = codex_outputs.reverse.find { |output| sha_match?(output["sha"], head) }
    request = issue_comments.select { |comment| codex_request?(comment["body"]) }.max_by { |comment| comment["created_at"].to_s }
    # Output produced after the request answers it when it reviewed the head or
    # the latest round head (a fix pushed after the round moves the head on
    # without a new request); a late review of an older head does not.
    answered = request && codex_outputs.any? do |output|
      (sha_match?(output["sha"], head) || (round_heads.last && sha_match?(output["sha"], round_heads.last))) &&
        Time.iso8601(output["at"]) > Time.iso8601(request["created_at"])
    end
    outstanding = nil
    if request && !answered
      # The 👀 reaction only says Codex started; a request with no durable output
      # after the timeout is dropped whether or not the reaction is still there.
      age = (now - Time.iso8601(request["created_at"])).to_i
      eyes = request.dig("reactions", "eyes").to_i.positive?
      outstanding = { "id" => request["id"], "created_at" => request["created_at"], "age_seconds" => age, "eyes" => eyes, "dropped" => age > REQUEST_TIMEOUT }
    end
    codex = {
      "sha" => codex_outputs.last&.dig("sha")&.slice(0, 7),
      "verdict" => codex_head&.dig("verdict"),
      "done_for_head" => !codex_head.nil?,
      "pending" => codex_head.nil? && !outstanding.nil? && !outstanding["dropped"],
      "outstanding_request" => outstanding
    }

    checks = Array(pull_request["statusCheckRollup"]).reject { |check| check_name(check).match?(/copilot/i) }
    failing = checks.reject { |check| check_green?(check) || check_pending?(check) }.map { |check| check_name(check) }
    pending_checks = checks.select { |check| check_pending?(check) }.map { |check| check_name(check) }
    ci = { "green" => checks.any? && failing.empty? && pending_checks.empty?, "failing" => failing, "pending" => pending_checks }

    # A ledger entry whose bot comment has since been deleted is no longer a
    # live finding, but until it reaches a terminal state it still blocks.
    live_ids = findings.map { |finding| finding["id"] }
    open_count = findings.count { |finding| !TERMINAL_STATUSES.include?(finding["ledger_status"]) }
    stale_open = ledger_entries.values.count do |entry|
      next false if live_ids.include?(entry["id"])
      if (problem = entry_problem(entry, ledger_entries.keys))
        warnings << "ledger entry #{entry["id"]}: #{problem}; treated as open"
      end
      problem || !TERMINAL_STATUSES.include?(entry["status"])
    end
    reasons = []
    reasons << "no Copilot review on this PR yet" if rounds.empty?
    if rounds.any? && codex_outputs.none? { |output| sha_match?(output["sha"], round_heads.last) }
      reasons << "Codex has not reviewed round head #{rounds.last}"
    end
    if open_count + stale_open > 0
      reasons << "#{open_count + stale_open} finding(s) not in a terminal state" \
                 "#{" (#{stale_open} no longer on the PR but still open in the ledger)" if stale_open > 0}"
    end
    reasons << (ci["failing"].any? ? "CI failing: #{ci["failing"].join(", ")}" : "CI not green yet") unless ci["green"]
    verification = ledger["verification"]
    if verification.nil? || !sha_match?(verification["head"], head)
      reasons << "fix delta not verified at head #{head7}"
    elsif verification["result"] != "clean"
      reasons << "fix delta verification at head #{head7} is #{verification["result"].inspect}, not clean"
    elsif round_heads.none? { |sha| sha_match?(verification["base"], sha) }
      reasons << "fix delta verification base #{verification["base"].inspect} is not a bot-reviewed head"
    end
    reasons << "a review request is still pending" if copilot["pending"] || codex["pending"]
    warnings << "base branch is #{pull_request["baseRefName"]}, not main: stacked PR, sweep the parent to a met stop state first" if pull_request["baseRefName"] != "main"

    {
      "pr" => pull_request["number"], "url" => pull_request["url"], "head" => head, "head7" => head7, "base" => pull_request["baseRefName"],
      "branch" => pull_request["headRefName"], "draft" => pull_request["isDraft"], "merge_state" => pull_request["mergeStateStatus"],
      "ci" => ci, "rounds" => rounds, "rounds_exhausted" => rounds.size >= MAX_ROUNDS,
      "reviews" => { "copilot" => copilot, "codex" => codex },
      "findings" => findings, "stop" => { "met" => reasons.empty?, "reasons" => reasons }, "warnings" => warnings
    }
  end

  # ---- Ledger --------------------------------------------------------------

  # A comment that carries the marker but no readable JSON is a broken ledger,
  # not an empty one: treating it as empty would let the next write discard
  # every adjudication it held.
  def parse_ledger(body)
    body = body.to_s.gsub("\r\n", "\n") # comments edited in the web UI come back with CRLF
    json = body[/```json\n(.*?)\n```/m, 1]
    if json.nil?
      raise FormatError, "the ledger comment carries the marker but no JSON block; refusing to treat it as empty" if body.start_with?(LEDGER_MARKER)
      return {}
    end
    parsed = JSON.parse(json)
    raise FormatError, "the ledger comment's JSON is not an object" unless parsed.is_a?(Hash)
    parsed
  rescue JSON::ParserError => error
    raise FormatError, "the ledger comment's JSON does not parse: #{error.message}"
  end

  # Merges the adjudications in `input` (the JSON a person or agent wrote) with
  # the live findings in `state`: live findings missing from the input are added
  # as open, entries for findings that have since vanished are kept as written,
  # and the identifying fields of every live finding are refreshed. Raises
  # ArgumentError on an entry that does not justify its status, or when the
  # input silently drops an entry the `existing` ledger already holds — an
  # entry leaves the ledger by reaching a terminal state, not by omission.
  def upsert_ledger(input, state, existing: {}, now: Time.now.utc)
    live = state["findings"].to_h { |finding| [ finding["id"], finding ] }
    raise ArgumentError, "every ledger entry needs an id" if Array(input["findings"]).any? { |entry| entry["id"].to_s.strip.empty? }
    entries = Array(input["findings"]).to_h { |entry| [ entry["id"], entry ] }
    dropped = Array(existing["findings"]).map { |entry| entry["id"] } - entries.keys
    raise ArgumentError, "input drops ledger entries #{dropped.join(", ")}; start from `bin/sweep-pr ledger N` output" if dropped.any?
    ids = entries.keys | live.keys
    findings = ids.map do |id|
      entry = (entries[id] || {}).merge("id" => id)
      status = entry.fetch("status", "open")
      raise ArgumentError, "#{id}: #{entry_problem(entry, ids)}" if entry_problem(entry, ids)
      if live[id] && resurfaced?(entry, live[id])
        raise ArgumentError, "#{id} resurfaced at #{live[id]["sha"]} after being fixed in #{entry["fixed_in"]}; " \
                             "re-adjudicate it and set its sha to #{live[id]["sha"]}"
      end
      (live[id] || entry).slice(*FINDING_FIELDS).merge(
        "status" => status, "note" => entry["note"].to_s, "fixed_in" => entry["fixed_in"], "duplicate_of" => entry["duplicate_of"]
      )
    end
    {
      "pr" => state["pr"], "head" => state["head7"], "rounds" => state["rounds"], "updated_at" => now.iso8601,
      "verification" => input["verification"], "findings" => findings
    }
  end

  def render_ledger(ledger, state)
    copilot = state.dig("reviews", "copilot")
    codex = state.dig("reviews", "codex")
    head7 = state["head7"]
    rounds = ledger["rounds"].size
    tallies = ledger["findings"].group_by { |finding| finding["status"] }
    verification = ledger["verification"]

    lines = [ LEDGER_MARKER, "## Review sweep", "" ]
    lines << "Maintained by the coding agent through `bin/sweep-pr`; rejected and deferred notes are the agent's judgment unless they say otherwise."
    lines << ""
    lines << [
      "Head #{head7}",
      "round #{rounds} of #{MAX_ROUNDS}#{" (exhausted)" if rounds >= MAX_ROUNDS}",
      if copilot["done_for_head"] then "Copilot reviewed #{head7} (#{copilot["inline"]} inline, #{copilot["suppressed"]} suppressed)"
      elsif copilot["pending"] then "Copilot review pending"
      else "Copilot has not reviewed #{head7}"
      end,
      if codex["done_for_head"] then "Codex reviewed #{head7} (#{codex["verdict"]})"
      elsif codex["pending"] then "Codex review pending"
      else "Codex has not reviewed #{head7}"
      end,
      if state.dig("ci", "green") then "CI green"
      elsif state.dig("ci", "failing").any? then "CI failing: #{state.dig("ci", "failing").join(", ")}"
      else "CI pending"
      end
    ].join(" · ")
    lines << "#{ledger["findings"].size} findings: " + STATUSES.filter_map { |status| "#{tallies[status].size} #{status}" if tallies[status] }.join(" · ")
    lines << if verification
      "Fix delta #{verification["base"]}..#{verification["head"]} reviewed locally: #{verification["result"]}#{" — #{verification["note"]}" unless verification["note"].to_s.empty?}"
    else
      "Fix delta not yet verified"
    end
    lines << "" << "<details><summary>Findings (#{ledger["findings"].size})</summary>" << ""
    lines << "| id | reviewer | location | title | status | resolution |" << "|---|---|---|---|---|---|"
    ledger["findings"].each do |finding|
      id = finding["url"] && finding["comment_id"] ? "[#{finding["id"]}](#{finding["url"]})" : cell(finding["id"])
      resolution = case finding["status"]
      when "fixed" then finding["fixed_in"]
      when "duplicate" then finding["duplicate_of"]
      else finding["note"].to_s[0, 140]
      end
      lines << "| #{id} | #{finding["reviewer"]} | #{cell("#{finding["path"]}:#{finding["line"]}")} | #{cell(finding["title"])} | #{finding["status"]} | #{cell(resolution)} |"
    end
    lines << "" << "</details>" << "" << "<details><summary>Ledger data (maintained by bin/sweep-pr)</summary>" << ""
    lines << "```json" << JSON.pretty_generate(ledger) << "```" << "</details>"
    lines.join("\n") + "\n"
  end

  def format_status(state, ledger)
    copilot = state.dig("reviews", "copilot")
    codex = state.dig("reviews", "codex")
    lines = []
    lines << "PR #{state["pr"]} #{state["url"]}"
    lines << "Head #{state["head7"]} on #{state["branch"]} -> #{state["base"]}#{" (draft)" if state["draft"]}, merge state #{state["merge_state"]}"
    ci = state["ci"]
    ci_text = if ci["green"] then "green"
    elsif ci["failing"].any? then "failing (#{ci["failing"].join(", ")})"
    elsif ci["pending"].any? then "pending (#{ci["pending"].join(", ")})"
    else "no checks reported"
    end
    lines << "CI: #{ci_text}"
    copilot_text = if copilot["done_for_head"]
      "reviewed #{state["head7"]}: #{copilot["headline"]} (#{copilot["inline"]} inline, #{copilot["suppressed"]} suppressed)#{", re-review pending" if copilot["pending"]}"
    elsif copilot["pending"] then "review pending for #{state["head7"]}"
    else "no review for #{state["head7"]}#{" (last reviewed #{copilot["sha"]})" if copilot["sha"]}"
    end
    lines << "Copilot: #{copilot_text}"
    request = codex["outstanding_request"]
    codex_text = if codex["done_for_head"] then "reviewed #{state["head7"]}: #{codex["verdict"]}"
    elsif codex["pending"]
      "review pending for #{state["head7"]} (request #{request["id"]}, #{request["age_seconds"] / 60} min old, eyes: #{request["eyes"] ? "yes" : "no"})"
    elsif request then "request #{request["id"]} looks dropped (#{request["age_seconds"] / 60} min, no output)"
    else "no review for #{state["head7"]}#{" (last reviewed #{codex["sha"]})" if codex["sha"]}"
    end
    lines << "Codex: #{codex_text}"
    lines << "Rounds: #{state["rounds"].size} of #{MAX_ROUNDS}#{" (exhausted)" if state["rounds_exhausted"]}#{" — #{state["rounds"].join(", ")}" if state["rounds"].any?}"
    tallies = state["findings"].group_by { |finding| finding["ledger_status"] }
    lines << "Findings: #{state["findings"].size} (#{STATUSES.filter_map { |status| "#{tallies[status].size} #{status}" if tallies[status] }.join(", ")})"
    lines << "Ledger: " + (ledger.empty? ? "none yet" : "updated #{ledger["updated_at"]} at head #{ledger["head"]}")
    verification = ledger["verification"]
    lines << "Verification: " + (verification ? "#{verification["base"]}..#{verification["head"]} #{verification["result"]}" : "none")
    state["warnings"].each { |warning| lines << "Warning: #{warning}" }
    lines << (state.dig("stop", "met") ? "Stop conditions: met" : "Stop conditions: not met — #{state.dig("stop", "reasons").join("; ")}")
    lines.join("\n") + "\n"
  end

  # ---- Helpers -------------------------------------------------------------

  # Why a ledger entry does not justify its status, or nil when it does.
  def entry_problem(entry, ids)
    status = entry.fetch("status", "open")
    return "unknown status #{status.inspect}" unless STATUSES.include?(status)
    return "#{status} needs a note" if %w[rejected deferred].include?(status) && entry["note"].to_s.strip.empty?
    return "fixed needs fixed_in set to a commit SHA" if status == "fixed" && !entry["fixed_in"].to_s.match?(/\A\h{7,40}\z/)
    if status == "duplicate" && (entry["duplicate_of"] == entry["id"] || !ids.include?(entry["duplicate_of"]))
      return "duplicate needs duplicate_of naming another ledger id"
    end
    nil
  end

  # A fixed finding seen again on a different head than the ledger recorded.
  def resurfaced?(entry, finding)
    entry["status"] == "fixed" && !entry["sha"].to_s.empty? && !sha_match?(finding["sha"], entry["sha"])
  end

  def suppressed_id(path, body)
    "copilot-suppressed:#{path}:#{Digest::SHA1.hexdigest(body.to_s.downcase.gsub(/\s+/, " ").strip)[0, 10]}"
  end

  def first_sentence(text)
    flat = text.to_s.gsub(/\s+/, " ").strip
    sentence = flat[/\A(.{1,120}?[.!?])(?:\s|\z)/, 1]
    sentence || (flat.length > 120 ? "#{flat[0, 119]}…" : flat)
  end

  def sha_match?(left, right)
    left = left.to_s
    right = right.to_s
    return false if left.length < 7 || right.length < 7
    left.start_with?(right) || right.start_with?(left)
  end

  def login(payload)
    payload.dig("user", "login")
  end

  def check_name(check)
    (check["name"] || check["context"]).to_s
  end

  def check_green?(check)
    if check["__typename"] == "StatusContext"
      check["state"] == "SUCCESS"
    else
      check["status"] == "COMPLETED" && %w[SUCCESS SKIPPED NEUTRAL].include?(check["conclusion"])
    end
  end

  def check_pending?(check)
    if check["__typename"] == "StatusContext"
      %w[PENDING EXPECTED].include?(check["state"])
    else
      check["status"] != "COMPLETED"
    end
  end

  def cell(text)
    text.to_s.gsub(/\r?\n/, " ").gsub("\\") { "\\\\" }.gsub("|") { "\\|" }.gsub(/#(\d+)/, 'issue \1')
  end
end
