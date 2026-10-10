# frozen_string_literal: true

# The pure half of bin/triage: turns the GraphQL payloads for the Honeyledger
# Projects v2 board into plain hashes, resolves Priority and Size option names
# to the IDs the mutation needs, derives Estimate from Size, and decides which
# issues still need triage.
# No network and no Rails here, so test/lib/project_board_test.rb can pin it
# with fixture payloads.
module ProjectBoard
  PROJECT_TITLE = "Honeyledger"
  TRIAGE_FIELDS = %w[Priority Size].freeze
  ESTIMATE_FIELD = "Estimate"
  # Estimate is never chosen on its own: it is Size as a number, so board
  # columns (which can only sum number fields) can total the work in them.
  ESTIMATES = { "XS" => 1, "S" => 2, "M" => 3, "L" => 5, "XL" => 8 }.freeze

  class Error < StandardError; end

  module_function

  # The project's single-select fields as
  # { "Priority" => { "id" => ..., "options" => { "P0" => ..., ... } }, ... }.
  # Option order is preserved, which is also their rank (P0 first, XS first).
  def single_select_fields(field_nodes)
    field_nodes.each_with_object({}) do |field, fields|
      next unless field["options"]

      options = field["options"].to_h { |option| [ option["name"], option["id"] ] }
      fields[field["name"]] = { "id" => field["id"], "options" => options }
    end
  end

  # The ID of any field by name, such as the Estimate number field.
  def field_id(field_nodes, name)
    field = field_nodes.find { |node| node["name"] == name } or raise Error, "The project has no #{name} field"
    field["id"]
  end

  # Resolves "Priority" + "P1" to [field_id, option_id], or raises with the
  # valid choices so a typo or a renamed option fails loudly.
  def option_id(fields, field_name, value)
    field = fields[field_name] or raise Error, "The project has no #{field_name} field"
    option = field["options"][value]
    raise Error, "#{field_name} has no option #{value.inspect}; choose one of #{field["options"].keys.join(", ")}" unless option

    [ field["id"], option ]
  end

  # Board items that are issues, as
  # { "item_id", "number", "title", "state", "labels", "repository", "Status", "Priority", "Size", "Estimate" }.
  # Pull requests and draft issues are dropped: only issues are triaged.
  def issues(item_nodes)
    item_nodes.filter_map do |item|
      content = item["content"] || {}
      next unless content["__typename"] == "Issue"

      values = item.dig("fieldValues", "nodes").to_a.each_with_object({}) do |value, collected|
        name = value.dig("field", "name")
        next unless name

        collected[name] = value.key?("number") ? whole(value["number"]) : value["name"]
      end
      {
        "item_id" => item["id"],
        "number" => content["number"],
        "title" => content["title"],
        "state" => content["state"],
        "labels" => content.dig("labels", "nodes").to_a.map { |label| label["name"] },
        "repository" => content.dig("repository", "nameWithOwner"),
        "Status" => values["Status"],
        "Priority" => values["Priority"],
        "Size" => values["Size"],
        "Estimate" => values[ESTIMATE_FIELD]
      }
    end
  end

  # GraphQL returns every number as a float; 3.0 reads better as 3.
  def whole(number)
    number == number.to_i ? number.to_i : number
  end

  # The Estimate an issue of this size should carry, or nil when it already
  # does or has no size to derive one from.
  def estimate_change(issue, size)
    expected = ESTIMATES[size] or return nil
    issue&.fetch(ESTIMATE_FIELD, nil) == expected ? nil : expected
  end

  def estimate_mismatch?(issue)
    !estimate_change(issue, issue["Size"]).nil?
  end

  # An open issue needs triage when Priority or Size is empty, or when its
  # Estimate is missing or does not match its Size.
  def untriaged?(issue)
    issue["state"] == "OPEN" && (TRIAGE_FIELDS.any? { |field| issue[field].nil? } || estimate_mismatch?(issue))
  end

  # The field changes `set` should make. A field that already holds a different
  # value is a maintainer's call and is refused unless `force` is given; setting
  # a field to the value it already has is a no-op. Estimate follows the Size
  # the issue will have, and is corrected without --force because it is never
  # a choice of its own.
  def changes(issue, requested, force: false)
    changes = requested.each_with_object({}) do |(field, value), collected|
      next if value.nil? || issue&.fetch(field, nil) == value

      current = issue&.fetch(field, nil)
      if current && !force
        raise Error, "Issue #{issue["number"]} already has #{field} #{current}; pass --force to change it to #{value}"
      end

      collected[field] = value
    end
    estimate = estimate_change(issue, changes["Size"] || issue&.fetch("Size", nil))
    estimate ? changes.merge(ESTIMATE_FIELD => estimate) : changes
  end

  def format_table(issues)
    return "Nothing to triage." if issues.empty?

    issues.sort_by { |issue| issue["number"] }.map do |issue|
      columns = [
        issue["number"].to_s.rjust(4),
        (issue["Priority"] || "-").ljust(2),
        (issue["Size"] || "-").ljust(2),
        "#{issue[ESTIMATE_FIELD] || "-"}#{"!" if estimate_mismatch?(issue)}".ljust(3),
        (issue["Status"] || "-").ljust(11),
        issue["title"]
      ]
      labels = issue["labels"].empty? ? "" : "  [#{issue["labels"].join(", ")}]"
      columns.join("  ") + labels
    end.join("\n")
  end
end
