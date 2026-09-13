require "test_helper"

class ReviewSweepTest < ActiveSupport::TestCase
  OLD_HEAD = "a" * 40
  HEAD = "b" * 40
  NOW = Time.utc(2026, 9, 13, 12, 0, 0)

  COPILOT_BODY = <<~MARKDOWN
    ### 🔵 Needs a closer look

    Two unresolved moderate findings remain.

    <details>
    <summary>Review details</summary>

    ### Suppressed comments (2)

    **app/controllers/widgets_controller.rb:15**
    * The success branch leaves a stale value in the session. Consume it before redirecting.
    ```
          redirect_to root_path, notice: "Done."
    ```
    **test/test_helpers/widget_helper.rb:13**
    * The helper deletes only the cookie and leaves the row behind,
      so later requests still authenticate.

    - **Files reviewed:** 3/3 changed files
    - **Comments generated:** 1
    - **Review effort level:** Lite
    </details>
  MARKDOWN

  CODEX_INLINE = <<~MARKDOWN
    **<sub><sub>![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)</sub></sub>  Reject submissions from signed-in sessions**

    A signed-in user can submit this endpoint again and open a second session.

    Useful? React with 👍 / 👎.
  MARKDOWN

  test "parses a Copilot review body into headline, suppressed findings, and generated count" do
    parsed = ReviewSweep.parse_copilot_review(COPILOT_BODY)

    assert_equal "🔵 Needs a closer look", parsed["headline"]
    assert_equal 1, parsed["generated"]
    assert_equal 2, parsed["suppressed"].size
    first, second = parsed["suppressed"]
    assert_equal "app/controllers/widgets_controller.rb", first["path"]
    assert_equal 15, first["line"]
    assert_equal "The success branch leaves a stale value in the session. Consume it before redirecting.", first["body"]
    assert_equal 13, second["line"]
    assert_equal "The helper deletes only the cookie and leaves the row behind, so later requests still authenticate.", second["body"]
  end

  test "a Copilot body whose declared count does not match what parsed is a format error" do
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_copilot_review(COPILOT_BODY.sub("(2)", "(3)")) }
    assert_equal [], ReviewSweep.parse_copilot_review("### 🟢 Looks good\n\nNothing to report.")["suppressed"]
  end

  test "parses a Codex inline comment into severity, title, and body without the footer" do
    parsed = ReviewSweep.parse_codex_comment(CODEX_INLINE)

    assert_equal "P2", parsed["severity"]
    assert_equal "Reject submissions from signed-in sessions", parsed["title"]
    assert_equal "A signed-in user can submit this endpoint again and open a second session.", parsed["body"]
  end

  test "recognizes Codex verdict comments and review requests" do
    clean = "Codex Review: Didn't find any major issues. Bravo.\n\n**Reviewed commit:** `#{HEAD[0, 10]}`"

    assert_equal HEAD[0, 10], ReviewSweep.codex_reviewed_sha(clean)
    assert ReviewSweep.codex_clean?(clean)
    assert_nil ReviewSweep.codex_reviewed_sha("no commit here")
    assert ReviewSweep.codex_request?("  @codex review \n")
    assert_not ReviewSweep.codex_request?("@codex address that feedback")
  end

  test "suppressed finding ids depend on the path and text, not on the head or line" do
    id = ReviewSweep.suppressed_id("app/models/widget.rb", "Something  is off.\nFix it.")

    assert_equal id, ReviewSweep.suppressed_id("app/models/widget.rb", "something is off. fix it.")
    assert_not_equal id, ReviewSweep.suppressed_id("app/models/gadget.rb", "Something is off. Fix it.")
    assert_match(/\Acopilot-suppressed:app\/models\/widget\.rb:\h{10}\z/, id)
  end

  test "assembles rounds, per-reviewer state, findings, and stop conditions from the raw payloads" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, check_runs: [], now: NOW)

    assert_equal [ OLD_HEAD[0, 7], HEAD[0, 7] ], state["rounds"]
    assert state["rounds_exhausted"]
    assert_equal %w[copilot:100 codex:300 codeql:400 copilot:200], state["findings"].select { |finding| finding["source"] == "inline" }.map { |finding| finding["id"] }
    assert_equal 2, state["findings"].count { |finding| finding["source"] == "suppressed" }
    assert_equal [ "open" ], state["findings"].map { |finding| finding["ledger_status"] }.uniq

    outdated = state["findings"].find { |finding| finding["id"] == "copilot:100" }
    assert outdated["outdated"]
    assert_equal 8, outdated["line"]
    assert_equal OLD_HEAD[0, 7], outdated["sha"]
    assert_equal [ "maintainer" ], outdated["replies"].map { |reply| reply["author"] }

    codex_finding = state["findings"].find { |finding| finding["id"] == "codex:300" }
    assert_equal "P2", codex_finding["severity"]
    assert_equal "CodeQL / Clear-text logging", state["findings"].find { |finding| finding["id"] == "codeql:400" }["title"]

    copilot = state.dig("reviews", "copilot")
    assert copilot["done_for_head"]
    assert_not copilot["pending"]
    assert_equal 1, copilot["inline"]
    assert_equal 2, copilot["suppressed"]
    codex = state.dig("reviews", "codex")
    assert codex["done_for_head"]
    assert_equal "clean", codex["verdict"]
    assert_nil codex["outstanding_request"]

    assert state.dig("ci", "green")
    assert_not state.dig("stop", "met")
    assert_equal [ "6 finding(s) not in a terminal state", "fix delta not verified at head #{HEAD[0, 7]}" ], state.dig("stop", "reasons")
    assert_empty state["warnings"]
  end

  test "a Codex request is pending while young and dropped once stale, whether or not it was acknowledged" do
    young = issue_comment(id: 900, login: "kramerc", body: "@codex review", at: NOW - 5 * 60)
    stale = issue_comment(id: 901, login: "kramerc", body: "@codex review", at: NOW - 20 * 60)
    acknowledged = stale.merge("reactions" => { "eyes" => 1 })

    pending = ReviewSweep.assemble(pull_request, [], [], [ young ], now: NOW).dig("reviews", "codex")
    assert pending["pending"]
    assert_not pending.dig("outstanding_request", "dropped")

    dropped = ReviewSweep.assemble(pull_request, [], [], [ stale ], now: NOW).dig("reviews", "codex")
    assert_not dropped["pending"]
    assert dropped.dig("outstanding_request", "dropped")

    stale_but_acknowledged = ReviewSweep.assemble(pull_request, [], [], [ acknowledged ], now: NOW).dig("reviews", "codex")
    assert_not stale_but_acknowledged["pending"]
    assert stale_but_acknowledged.dig("outstanding_request", "eyes")
    assert stale_but_acknowledged.dig("outstanding_request", "dropped")

    assert_equal [ "no Copilot review on this PR yet", "1 finding(s) not in a terminal state", "fix delta not verified at head #{HEAD[0, 7]}" ],
                 ReviewSweep.assemble(pull_request, [], [ review_comments.last ], [], now: NOW).dig("stop", "reasons").tap { |reasons| reasons.delete_if { |reason| reason.start_with?("CI") } }
  end

  test "the stop conditions require a clean verification and count open ledger entries whose comment vanished" do
    terminal = { "findings" => [], "verification" => { "base" => OLD_HEAD[0, 7], "head" => HEAD[0, 7], "result" => "clean" } }
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    terminal["findings"] = state["findings"].map { |finding| { "id" => finding["id"], "status" => "fixed", "fixed_in" => "c" * 7 } }
    assert ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: terminal, now: NOW).dig("stop", "met")

    not_clean = terminal.merge("verification" => terminal["verification"].merge("result" => "issues found"))
    reasons = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: not_clean, now: NOW).dig("stop", "reasons")
    assert_equal [ "fix delta verification at head #{HEAD[0, 7]} is \"issues found\", not clean" ], reasons

    stale_entry = terminal.merge("findings" => terminal["findings"] + [ { "id" => "copilot:999", "status" => "accepted" } ])
    reasons = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: stale_entry, now: NOW).dig("stop", "reasons")
    assert_equal [ "1 finding(s) not in a terminal state (1 no longer on the PR but still open in the ledger)" ], reasons
  end

  test "a suppressed-comments heading without a count and a marked ledger without JSON are format errors" do
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_copilot_review("### Suppressed comments (many)\n\n**a.rb:1**\n* text") }
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_ledger("#{ReviewSweep::LEDGER_MARKER}\n## Review sweep\n\nno data") }
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_ledger("#{ReviewSweep::LEDGER_MARKER}\n```json\n{ not json\n```") }
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_ledger("#{ReviewSweep::LEDGER_MARKER}\n```json\nnull\n```") }
    assert_raises(ReviewSweep::FormatError) { ReviewSweep.parse_ledger("#{ReviewSweep::LEDGER_MARKER}\n```json\n[]\n```") }
    assert_equal({ "pr" => 1 }, ReviewSweep.parse_ledger("#{ReviewSweep::LEDGER_MARKER}\r\n## Review sweep\r\n```json\r\n{ \"pr\": 1 }\r\n```\r\n"))
    assert_equal({}, ReviewSweep.parse_ledger("An unrelated comment"))
  end

  test "table cells escape backslashes and pipes and never carry a bare issue reference" do
    assert_equal "a\\\\b\\|c issue 12", ReviewSweep.cell("a\\b|c #12")
    long = "x" * 200
    assert_not_equal ReviewSweep.suppressed_id("a.rb", "#{long} first"), ReviewSweep.suppressed_id("a.rb", "#{long} second")
  end

  test "rounds are counted on full commit ids and Copilot is pending while any check-run attempt is running" do
    near_miss = HEAD[0, 7] + "c" * 33
    two_rounds = [
      review(id: 20, login: ReviewSweep::COPILOT_REVIEWER, sha: HEAD, at: NOW - 600, body: COPILOT_BODY),
      review(id: 21, login: ReviewSweep::COPILOT_REVIEWER, sha: near_miss, at: NOW - 300, body: "### 🟢 Looks good")
    ]
    assert_equal 2, ReviewSweep.assemble(pull_request, two_rounds, [], [], now: NOW)["rounds"].size

    attempts = [
      { "name" => ReviewSweep::COPILOT_CHECK_RUN, "status" => "completed" },
      { "name" => ReviewSweep::COPILOT_CHECK_RUN, "status" => "in_progress" }
    ]
    assert ReviewSweep.assemble(pull_request, [], [], [], check_runs: attempts, now: NOW).dig("reviews", "copilot", "pending")
  end

  test "a Codex request is answered only by output for the head that arrives after it" do
    request = issue_comment(id: 900, login: "kramerc", body: "@codex review", at: NOW - 5 * 60)
    old_head_output = issue_comment(id: 901, login: ReviewSweep::CODEX, body: "Codex Review: Didn't find any major issues.\n\n**Reviewed commit:** `#{OLD_HEAD[0, 10]}`", at: NOW - 60)
    head_output = issue_comment(id: 902, login: ReviewSweep::CODEX, body: "Codex Review: Didn't find any major issues.\n\n**Reviewed commit:** `#{HEAD[0, 10]}`", at: NOW - 60)

    late_old = ReviewSweep.assemble(pull_request, [], [], [ request, old_head_output ], now: NOW).dig("reviews", "codex")
    assert late_old["pending"]
    assert_not late_old["done_for_head"]

    answered = ReviewSweep.assemble(pull_request, [], [], [ request, head_output ], now: NOW).dig("reviews", "codex")
    assert answered["done_for_head"]
    assert_nil answered["outstanding_request"]

    # A fix pushed after the round moves the head on; the answer for the round head still counts.
    moved_on = pull_request.merge("headRefOid" => "e" * 40)
    round_at_head = [ review(id: 20, login: ReviewSweep::COPILOT_REVIEWER, sha: HEAD, at: NOW - 600, body: "### 🟢 Looks good") ]
    after_fix = ReviewSweep.assemble(moved_on, round_at_head, [], [ request, head_output ], now: NOW).dig("reviews", "codex")
    assert_not after_fix["done_for_head"]
    assert_not after_fix["pending"]
    assert_nil after_fix["outstanding_request"]
  end

  test "a fixed finding that resurfaces on a later head is open again and must be re-adjudicated" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    resurfaced_id = state["findings"].find { |finding| finding["source"] == "suppressed" }["id"]
    ledger = { "findings" => [ { "id" => resurfaced_id, "status" => "fixed", "fixed_in" => "c" * 7, "sha" => OLD_HEAD[0, 7] } ] }

    reopened = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: ledger, now: NOW)
    assert_equal "open", reopened["findings"].find { |finding| finding["id"] == resurfaced_id }["ledger_status"]
    assert_match(/resurfaced at #{HEAD[0, 7]} after being fixed in ccccccc/, reopened["warnings"].first)

    error = assert_raises(ArgumentError) { ReviewSweep.upsert_ledger(ledger, state, now: NOW) }
    assert_match(/resurfaced/, error.message)
    acknowledged = { "findings" => [ ledger["findings"].first.merge("sha" => HEAD) ] } # a full SHA matches the short live one
    assert_equal "fixed", ReviewSweep.upsert_ledger(acknowledged, state, now: NOW)["findings"].find { |finding| finding["id"] == resurfaced_id }["status"]

    untouched = { "findings" => [
      { "id" => resurfaced_id, "status" => "fixed", "fixed_in" => "c" * 7 }, # written before entries carried a sha
      { "id" => "copilot:100", "status" => "fixed", "fixed_in" => "c" * 7, "sha" => OLD_HEAD[0, 7] } # inline: sha never moves
    ] }
    statuses = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: untouched, now: NOW)["findings"]
      .select { |finding| [ resurfaced_id, "copilot:100" ].include?(finding["id"]) }.map { |finding| finding["ledger_status"] }
    assert_equal %w[fixed fixed], statuses
  end

  test "a ledger entry that does not justify its status is treated as open, and entries need ids" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    corrupt = { "findings" => [ { "id" => "copilot:100", "status" => "fixed" }, { "id" => "copilot:200", "status" => "rejected", "note" => "" } ] }

    checked = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: corrupt, now: NOW)
    assert_equal %w[open open], checked["findings"].select { |finding| %w[copilot:100 copilot:200].include?(finding["id"]) }.map { |finding| finding["ledger_status"] }
    assert_equal 2, checked["warnings"].count { |warning| warning.include?("treated as open") }

    stale_corrupt = { "findings" => [ { "id" => "copilot:999", "status" => "fixed" } ] }
    stale_state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: stale_corrupt, now: NOW)
    assert_includes stale_state["warnings"], "ledger entry copilot:999: fixed needs fixed_in set to a commit SHA; treated as open"
    assert_includes stale_state.dig("stop", "reasons").join, "(1 no longer on the PR but still open in the ledger)"

    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "status" => "accepted" } ] }, state) }
  end

  test "the stop conditions need Codex on the latest round head, a bot-reviewed verification base, and no pending request" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    terminal = state["findings"].map { |finding| { "id" => finding["id"], "status" => "fixed", "fixed_in" => "c" * 7 } }
    ledger = { "findings" => terminal, "verification" => { "base" => "d" * 7, "head" => HEAD[0, 7], "result" => "clean" } }
    reasons = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: ledger, now: NOW).dig("stop", "reasons")
    assert_equal [ "fix delta verification base \"ddddddd\" is not a bot-reviewed head" ], reasons

    ledger["verification"]["base"] = OLD_HEAD[0, 7]
    without_codex = issue_comments.reject { |comment| [ 501, 502 ].include?(comment["id"]) }
    reasons = ReviewSweep.assemble(pull_request, reviews, review_comments, without_codex, ledger: ledger, now: NOW).dig("stop", "reasons")
    assert_equal [ "Codex has not reviewed round head #{HEAD[0, 7]}" ], reasons

    requested = pull_request.merge("reviewRequests" => [ { "login" => "copilot-pull-request-reviewer" } ])
    reasons = ReviewSweep.assemble(requested, reviews, review_comments, issue_comments, ledger: ledger, now: NOW).dig("stop", "reasons")
    assert_equal [ "a review request is still pending" ], reasons
  end

  test "the ledger table shows the fixing commit, the duplicate target, and the verification line" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    input = {
      "verification" => { "base" => OLD_HEAD[0, 7], "head" => HEAD[0, 7], "result" => "clean", "note" => "fresh subagent" },
      "findings" => [
        { "id" => "copilot:100", "status" => "fixed", "fixed_in" => "c" * 7 },
        { "id" => "copilot:200", "status" => "duplicate", "duplicate_of" => "copilot:100" }
      ]
    }
    rendered = ReviewSweep.render_ledger(ReviewSweep.upsert_ledger(input, state, now: NOW), state)

    assert_includes rendered, "Fix delta #{OLD_HEAD[0, 7]}..#{HEAD[0, 7]} reviewed locally: clean — fresh subagent"
    assert_includes rendered, "| fixed | #{"c" * 7} |"
    assert_includes rendered, "| duplicate | copilot:100 |"

    older_only = ReviewSweep.assemble(pull_request, [ reviews[2] ], [], [], now: NOW)
    assert_includes ReviewSweep.format_status(older_only, {}), "Codex: no review for #{HEAD[0, 7]} (last reviewed #{OLD_HEAD[0, 7]})"
  end

  test "status and ledger text describe pending, dropped, failing, and unreviewed states" do
    stalled = pull_request.merge(
      "reviewRequests" => [ { "__typename" => "Bot", "login" => "copilot-pull-request-reviewer" } ],
      "statusCheckRollup" => [
        { "__typename" => "CheckRun", "name" => "test", "status" => "COMPLETED", "conclusion" => "FAILURE" },
        { "__typename" => "StatusContext", "context" => "codecov/patch", "state" => "PENDING" }
      ]
    )
    dropped = issue_comment(id: 901, login: "kramerc", body: "@codex review", at: NOW - 20 * 60)
    state = ReviewSweep.assemble(stalled, [], [], [ dropped ], now: NOW)
    ledger = ReviewSweep.upsert_ledger({}, state, now: NOW)

    status = ReviewSweep.format_status(state, ledger)
    assert_includes status, "CI: failing (test)"
    assert_includes status, "Copilot: review pending for #{HEAD[0, 7]}"
    assert_includes status, "Codex: request 901 looks dropped (20 min, no output)"
    assert_includes status, "Stop conditions: not met — no Copilot review on this PR yet; CI failing: test; fix delta not verified"
    rendered = ReviewSweep.render_ledger(ledger, state)
    assert_includes rendered, "round 0 of 2 · Copilot review pending · Codex has not reviewed #{HEAD[0, 7]} · CI failing: test"
    assert_includes rendered, "0 findings: "
    assert_includes rendered, "Fix delta not yet verified"

    young = issue_comment(id: 902, login: "kramerc", body: "@codex review", at: NOW - 60).merge("reactions" => { "eyes" => 1 })
    codex_findings_review = review(id: 31, login: ReviewSweep::CODEX, sha: HEAD, at: NOW - 30, body: "### 💡 Codex Review\n\n**Reviewed commit:** `#{HEAD[0, 10]}`")
    quiet = pull_request.merge("statusCheckRollup" => [])
    state = ReviewSweep.assemble(quiet, [], [], [ young ], now: NOW)
    assert_includes ReviewSweep.format_status(state, {}), "Codex: review pending for #{HEAD[0, 7]} (request 902, 1 min old, eyes: yes)"
    assert_includes ReviewSweep.format_status(state, {}), "CI: no checks reported"
    assert_includes ReviewSweep.render_ledger(ReviewSweep.upsert_ledger({}, state, now: NOW), state), "Copilot has not reviewed #{HEAD[0, 7]} · Codex review pending · CI pending"

    state = ReviewSweep.assemble(pull_request.merge("statusCheckRollup" => [ { "__typename" => "CheckRun", "name" => "test", "status" => "IN_PROGRESS", "conclusion" => nil } ]),
                                 [ codex_findings_review ], [], [], now: NOW)
    assert_includes ReviewSweep.format_status(state, {}), "Codex: reviewed #{HEAD[0, 7]}: findings"
    assert_includes ReviewSweep.format_status(state, {}), "CI: pending (test)"
    assert_includes ReviewSweep.format_status(state, {}), "Copilot: no review for #{HEAD[0, 7]}"
  end

  test "Copilot is pending when requested or when its check run has not completed" do
    requested = pull_request.merge("reviewRequests" => [ { "__typename" => "Bot", "login" => "copilot-pull-request-reviewer" } ])
    assert ReviewSweep.assemble(requested, [], [], [], now: NOW).dig("reviews", "copilot", "pending")

    running = [ { "name" => ReviewSweep::COPILOT_CHECK_RUN, "status" => "in_progress" } ]
    assert ReviewSweep.assemble(pull_request, [], [], [], check_runs: running, now: NOW).dig("reviews", "copilot", "pending")
    assert_not ReviewSweep.assemble(pull_request, [], [], [], now: NOW).dig("reviews", "copilot", "pending")
  end

  test "a mismatch between Copilot's generated count and the inline comments present is a warning, not an error" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments.reject { |comment| comment["id"] == 200 }, issue_comments, now: NOW)

    assert_equal 1, state["warnings"].size
    assert_match(/says it generated 1 comments but 0 are present/, state["warnings"].first)
  end

  test "upsert_ledger validates every entry, adds missing live findings as open, and refreshes identifying fields" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    input = {
      "verification" => { "base" => OLD_HEAD[0, 7], "head" => HEAD[0, 7], "result" => "clean" },
      "findings" => [
        { "id" => "copilot:100", "status" => "fixed", "fixed_in" => "c" * 7, "path" => "stale/path.rb" },
        { "id" => "codex:300", "status" => "duplicate", "duplicate_of" => "copilot:100" },
        { "id" => "copilot:999", "status" => "rejected", "note" => "Comment was deleted but the decision stands.", "path" => "gone.rb" }
      ]
    }

    ledger = ReviewSweep.upsert_ledger(input, state, now: NOW)

    assert_equal 7, ledger["findings"].size
    fixed = ledger["findings"].find { |finding| finding["id"] == "copilot:100" }
    assert_equal "app/models/widget.rb", fixed["path"]
    assert_equal "c" * 7, fixed["fixed_in"]
    assert_equal "gone.rb", ledger["findings"].find { |finding| finding["id"] == "copilot:999" }["path"]
    assert_equal 4, ledger["findings"].count { |finding| finding["status"] == "open" }
    assert_equal HEAD[0, 7], ledger["head"]
    assert_equal NOW.iso8601, ledger["updated_at"]

    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "id" => "copilot:100", "status" => "done" } ] }, state) }
    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "id" => "copilot:100", "status" => "rejected" } ] }, state) }
    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "id" => "copilot:100", "status" => "fixed" } ] }, state) }
    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "id" => "copilot:100", "status" => "fixed", "fixed_in" => "later" } ] }, state) }
    error = assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [] }, state, existing: ledger) }
    assert_match(/drops ledger entries copilot:100/, error.message)
    assert_equal 7, ReviewSweep.upsert_ledger({ "findings" => ledger["findings"] }, state, existing: ledger)["findings"].size
    assert_raises(ArgumentError) { ReviewSweep.upsert_ledger({ "findings" => [ { "id" => "copilot:100", "status" => "duplicate", "duplicate_of" => "copilot:100" } ] }, state) }
  end

  test "parses the Codex summary table into review, status, commit, and completion time" do
    completed = ReviewSweep.parse_codex_summary(codex_summary(sha: HEAD, status: "✅ **Completed**", completed_at: NOW))
    assert_equal [ { "review" => "Code Review", "status" => "completed", "sha" => HEAD[0, 7], "completed_at" => NOW.utc.iso8601(6) } ], completed

    assert_equal "running", ReviewSweep.parse_codex_summary(codex_summary(sha: HEAD, status: "⏳ **In progress**")).first["status"]
    assert_equal "failed", ReviewSweep.parse_codex_summary(codex_summary(sha: HEAD, status: "❌ **Failed**")).first["status"]
    assert_equal [], ReviewSweep.parse_codex_summary("#{ReviewSweep::CODEX_SUMMARY_MARKER}\n\nNo reviews yet.")
  end

  test "a completed Codex summary row at the head is a clean review that answers a request and is never a finding" do
    request = issue_comment(id: 900, login: "kramerc", body: "@codex review", at: NOW - 20 * 60)
    summary = issue_comment(id: 901, login: ReviewSweep::CODEX, body: codex_summary(sha: HEAD, status: "✅ **Completed**", completed_at: NOW - 60),
                            at: NOW - 3600, updated_at: NOW - 59)
    copilot_round = [ review(id: 20, login: ReviewSweep::COPILOT_REVIEWER, sha: HEAD, at: NOW - 600, body: "### 🟢 Looks good") ]

    state = ReviewSweep.assemble(pull_request, copilot_round, [], [ request, summary ], now: NOW)
    codex = state.dig("reviews", "codex")
    assert codex["done_for_head"]
    assert_equal "clean", codex["verdict"]
    assert_not codex["pending"]
    assert_nil codex["outstanding_request"]
    assert_empty state["findings"]
    assert_empty state["warnings"]
    assert_not_includes state.dig("stop", "reasons").join, "Codex"
    assert_includes ReviewSweep.format_status(state, {}), "Codex: reviewed #{HEAD[0, 7]}: clean"
  end

  test "a Codex summary row for an older commit does not count for the head" do
    summary = issue_comment(id: 901, login: ReviewSweep::CODEX, body: codex_summary(sha: OLD_HEAD, status: "✅ **Completed**", completed_at: NOW - 60), at: NOW - 3600)

    state = ReviewSweep.assemble(pull_request, [], [], [ summary ], now: NOW)
    assert_not state.dig("reviews", "codex", "done_for_head")
    assert_not state.dig("reviews", "codex", "pending")
    assert_includes ReviewSweep.format_status(state, {}), "Codex: no review for #{HEAD[0, 7]} (last reviewed #{OLD_HEAD[0, 7]})"
  end

  test "a completed Codex summary row is findings when Codex left a review for that commit" do
    summary = issue_comment(id: 901, login: ReviewSweep::CODEX, body: codex_summary(sha: HEAD, status: "✅ **Completed**", completed_at: NOW - 30), at: NOW - 3600)
    codex_review = review(id: 31, login: ReviewSweep::CODEX, sha: HEAD, at: NOW - 60, body: "### 💡 Codex Review")
    inline = review_comment(id: 301, login: ReviewSweep::CODEX, review_id: 31, path: "app/models/widget.rb", line: 4, original_line: 4, body: CODEX_INLINE, at: NOW - 60)

    state = ReviewSweep.assemble(pull_request, [ codex_review ], [ inline ], [ summary ], now: NOW)
    assert state.dig("reviews", "codex", "done_for_head")
    assert_equal "findings", state.dig("reviews", "codex", "verdict")
    assert_equal %w[codex:301], state["findings"].map { |finding| finding["id"] }
  end

  test "a completed Codex summary row is findings when Codex left only inline comments for that commit" do
    summary = issue_comment(id: 901, login: ReviewSweep::CODEX, body: codex_summary(sha: HEAD, status: "✅ **Completed**", completed_at: NOW - 30), at: NOW - 3600)
    inline = review_comment(id: 301, login: ReviewSweep::CODEX, review_id: 31, path: "app/models/widget.rb", line: 4, original_line: 4, body: CODEX_INLINE,
                            at: NOW - 60, original_commit: HEAD)

    state = ReviewSweep.assemble(pull_request, [], [ inline ], [ summary ], now: NOW)
    assert state.dig("reviews", "codex", "done_for_head")
    assert_equal "findings", state.dig("reviews", "codex", "verdict")
  end

  test "a running Codex summary row at the head is pending until it goes stale, and keeps a request from looking dropped" do
    running = codex_summary(sha: HEAD, status: "⏳ **In progress**")
    request = issue_comment(id: 900, login: "kramerc", body: "@codex review", at: NOW - 20 * 60)

    fresh = ReviewSweep.assemble(pull_request, [], [], [ issue_comment(id: 901, login: ReviewSweep::CODEX, body: running, at: NOW - 3600, updated_at: NOW - 120) ], now: NOW)
    assert fresh.dig("reviews", "codex", "pending")
    assert_not fresh.dig("reviews", "codex", "done_for_head")
    assert_includes ReviewSweep.format_status(fresh, {}), "Codex: review running for #{HEAD[0, 7]}"

    with_request = ReviewSweep.assemble(pull_request, [], [], [ request, issue_comment(id: 901, login: ReviewSweep::CODEX, body: running, at: NOW - 3600, updated_at: NOW - 120) ], now: NOW)
    assert with_request.dig("reviews", "codex", "pending")
    assert_not with_request.dig("reviews", "codex", "outstanding_request", "dropped")

    stale = ReviewSweep.assemble(pull_request, [], [], [ issue_comment(id: 901, login: ReviewSweep::CODEX, body: running, at: NOW - 3600, updated_at: NOW - 3600) ], now: NOW)
    assert_not stale.dig("reviews", "codex", "pending")

    failed = ReviewSweep.assemble(pull_request, [], [], [ issue_comment(id: 901, login: ReviewSweep::CODEX, body: codex_summary(sha: HEAD, status: "❌ **Failed**"), at: NOW - 60) ], now: NOW)
    assert_not failed.dig("reviews", "codex", "pending")
    assert_not failed.dig("reviews", "codex", "done_for_head")

    security_only = codex_summary(sha: HEAD, status: "✅ **Completed**", completed_at: NOW - 60, review: "🔒 **Security Review**")
    assert_not ReviewSweep.assemble(pull_request, [], [], [ issue_comment(id: 901, login: ReviewSweep::CODEX, body: security_only, at: NOW - 60) ], now: NOW).dig("reviews", "codex", "done_for_head")
  end

  test "a Codex summary table with no row that parses is a warning" do
    broken = issue_comment(id: 901, login: ReviewSweep::CODEX, body: "#{ReviewSweep::CODEX_SUMMARY_MARKER}\n\n| Review | Status |\n| --- | --- |", at: NOW - 60)

    assert_includes ReviewSweep.assemble(pull_request, [], [], [ broken ], now: NOW)["warnings"].join, "Codex summary comment 901 has a table but no row parsed"
  end

  test "the rendered ledger round-trips through parse_ledger and feeds the next assemble" do
    state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, now: NOW)
    input = { "findings" => [ { "id" => "copilot:200", "status" => "deferred", "note" => "Tracked in #12 | later" } ] }
    ledger = ReviewSweep.upsert_ledger(input, state, now: NOW)

    body = ReviewSweep.render_ledger(ledger, state)

    assert body.start_with?("#{ReviewSweep::LEDGER_MARKER}\n## Review sweep\n")
    assert_includes body, "Maintained by the coding agent"
    assert_includes body, "round 2 of 2 (exhausted)"
    assert_includes body, "Copilot reviewed #{HEAD[0, 7]} (1 inline, 2 suppressed)"
    assert_includes body, "6 findings: 5 open · 1 deferred"
    assert_includes body, "| deferred | Tracked in issue 12 \\| later |"
    assert_equal 6, body.scan(/^\| \S+ \| (?:copilot|codex|codeql) \|/).size
    assert_equal ledger, ReviewSweep.parse_ledger(body)

    next_state = ReviewSweep.assemble(pull_request, reviews, review_comments, issue_comments, ledger: ReviewSweep.parse_ledger(body), now: NOW)
    assert_equal "deferred", next_state["findings"].find { |finding| finding["id"] == "copilot:200" }["ledger_status"]
    assert_includes ReviewSweep.format_status(next_state, ledger), "Findings: 6 (5 open, 1 deferred)"
  end

  private
    def pull_request
      {
        "number" => 1, "url" => "https://example.test/pr/1", "isDraft" => false, "headRefOid" => HEAD,
        "headRefName" => "feature", "baseRefName" => "main", "reviewRequests" => [], "mergeStateStatus" => "CLEAN",
        "statusCheckRollup" => [
          { "__typename" => "CheckRun", "name" => "test", "status" => "COMPLETED", "conclusion" => "SUCCESS" },
          { "__typename" => "StatusContext", "context" => "codecov/patch", "state" => "SUCCESS" },
          { "__typename" => "CheckRun", "name" => ReviewSweep::COPILOT_CHECK_RUN, "status" => "IN_PROGRESS", "conclusion" => nil }
        ]
      }
    end

    def reviews
      [
        review(id: 10, login: ReviewSweep::COPILOT_REVIEWER, sha: OLD_HEAD, at: NOW - 3600,
               body: "### 🟡 Changes recommended\n\n<details>\n<summary>Review details</summary>\n\n- **Comments generated:** 1\n</details>"),
        review(id: 20, login: ReviewSweep::COPILOT_REVIEWER, sha: HEAD, at: NOW - 600, body: COPILOT_BODY),
        review(id: 30, login: ReviewSweep::CODEX, sha: OLD_HEAD, at: NOW - 3500, body: "### 💡 Codex Review\n\n**Reviewed commit:** `#{OLD_HEAD[0, 10]}`"),
        review(id: 40, login: "kramerc", sha: OLD_HEAD, at: NOW - 3000, body: "")
      ]
    end

    def review_comments
      [
        review_comment(id: 100, login: ReviewSweep::COPILOT_COMMENTER, review_id: 10, path: "app/models/widget.rb", line: nil, original_line: 8,
                       body: "This omits a guard. Add one.", at: NOW - 3600),
        review_comment(id: 101, login: "maintainer", review_id: 40, path: "app/models/widget.rb", line: nil, original_line: 8,
                       body: "Fixed in ccccccc.", at: NOW - 3000, in_reply_to: 100),
        review_comment(id: 200, login: ReviewSweep::COPILOT_COMMENTER, review_id: 20, path: "app/controllers/widgets_controller.rb", line: 59, original_line: 59,
                       body: "The cookie is not marked Secure.", at: NOW - 600),
        review_comment(id: 300, login: ReviewSweep::CODEX, review_id: 30, path: "app/controllers/widgets_controller.rb", line: 2, original_line: 2,
                       body: CODEX_INLINE, at: NOW - 3500),
        review_comment(id: 400, login: ReviewSweep::CODEQL, review_id: 50, path: "app/controllers/widgets_controller.rb", line: nil, original_line: 20,
                       body: "## CodeQL / Clear-text logging\n\nThis logs sensitive data.", at: NOW - 3400)
      ]
    end

    def issue_comments
      [
        issue_comment(id: 500, login: ReviewSweep::CODEX, body: codex_summary(sha: OLD_HEAD, status: "✅ **Completed**", completed_at: NOW - 3500), at: NOW - 3600),
        issue_comment(id: 501, login: "kramerc", body: "@codex review", at: NOW - 900),
        issue_comment(id: 502, login: ReviewSweep::CODEX, body: "Codex Review: Didn't find any major issues.\n\n**Reviewed commit:** `#{HEAD[0, 10]}`", at: NOW - 500),
        issue_comment(id: 503, login: "codecov[bot]", body: "All modified lines are covered.", at: NOW - 400)
      ]
    end

    def review(id:, login:, sha:, at:, body:)
      { "id" => id, "user" => { "login" => login }, "commit_id" => sha, "submitted_at" => at.iso8601, "body" => body,
        "html_url" => "https://example.test/pr/1#pullrequestreview-#{id}" }
    end

    def review_comment(id:, login:, review_id:, path:, line:, original_line:, body:, at:, in_reply_to: nil, original_commit: OLD_HEAD)
      { "id" => id, "user" => { "login" => login }, "pull_request_review_id" => review_id, "path" => path, "line" => line,
        "original_line" => original_line, "original_commit_id" => original_commit, "body" => body, "created_at" => at.iso8601,
        "in_reply_to_id" => in_reply_to, "html_url" => "https://example.test/pr/1#discussion_r#{id}" }
    end

    def issue_comment(id:, login:, body:, at:, updated_at: at)
      { "id" => id, "user" => { "login" => login }, "body" => body, "created_at" => at.iso8601, "updated_at" => updated_at.iso8601,
        "reactions" => { "eyes" => 0 } }
    end

    def codex_summary(sha:, status:, completed_at: nil, review: "📝 **Code Review**")
      timestamp = completed_at && completed_at.utc.iso8601(6)
      status_cell = timestamp ? "#{status} <relative-time datetime=\"#{timestamp}\">#{timestamp}</relative-time>" : status
      <<~MARKDOWN
        #{ReviewSweep::CODEX_SUMMARY_MARKER}

        ## Codex Review Summary

        | Review | Status | Commit | Review trigger |
        | --- | --- | --- | --- |
        | #{review} | #{status_cell} | `#{sha[0, 7]}` | PR opened |

        <details> <summary>About Codex in GitHub</summary>

        Codex reacts with 👀 while any review is running, comments if it has suggestions, and reacts with 👍 once all reviews finish with no findings.

        </details>
      MARKDOWN
    end
end
