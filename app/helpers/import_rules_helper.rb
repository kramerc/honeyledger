module ImportRulesHelper
  MATCH_TYPE_SHORT = {
    "contains" => "Contains",
    "exact" => "Exact",
    "starts_with" => "Starts",
    "ends_with" => "Ends"
  }.freeze

  MATCH_TYPE_PHRASE = {
    "contains" => "contains",
    "exact" => "is exactly",
    "starts_with" => "starts with",
    "ends_with" => "ends with"
  }.freeze

  # Live preview for a rule's current attributes, so the editor can render its matches
  # server-side (no "start typing" flash + round-trip when editing an existing rule).
  def import_rule_live_preview(rule)
    ImportRule::MatchPreview.new(
      user: current_user,
      pattern: rule.match_pattern,
      match_type: rule.match_type,
      account_id: rule.account_id,
      exclude: rule.exclude
    )
  end

  # Label for the editor's segmented match-type control.
  def match_type_short_label(match_type)
    MATCH_TYPE_SHORT[match_type.to_s] || match_type.to_s.humanize
  end

  # Phrase shown in the list chip ("contains", "is exactly", …).
  def match_type_phrase(match_type)
    MATCH_TYPE_PHRASE[match_type.to_s] || match_type.to_s.humanize
  end

  # Wrap the portion of a description that a (pattern, match_type) hits in <mark>,
  # for the live preview. Mirrors ImportRule's case-insensitive matching.
  def highlight_match(description, pattern, match_type)
    pattern = pattern.to_s.strip
    return description if pattern.blank?

    lower = description.downcase
    needle = pattern.downcase

    start, finish =
      case match_type.to_s
      when "exact"
        lower == needle ? [ 0, description.length ] : [ nil, nil ]
      when "starts_with"
        lower.start_with?(needle) ? [ 0, needle.length ] : [ nil, nil ]
      when "ends_with"
        lower.end_with?(needle) ? [ description.length - needle.length, description.length ] : [ nil, nil ]
      else
        index = lower.index(needle)
        index ? [ index, index + needle.length ] : [ nil, nil ]
      end

    return description if start.nil?

    safe_join([
      description[0...start],
      tag.mark(description[start...finish], class: "ir-mark"),
      description[finish..]
    ])
  end
end
