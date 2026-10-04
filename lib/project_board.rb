# frozen_string_literal: true

# The pure half of bin/triage: turns the GraphQL payloads for the Honeyledger
# Projects v2 board into plain hashes, resolves Priority and Size option names
# to the IDs the mutation needs, and decides which issues still need triage.
# No network and no Rails here, so test/lib/project_board_test.rb can pin it
# with fixture payloads.
module ProjectBoard
  PROJECT_TITLE = "Honeyledger"
  TRIAGE_FIELDS = %w[Priority Size].freeze

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

  # Resolves "Priority" + "P1" to [field_id, option_id], or raises with the
  # valid choices so a typo or a renamed option fails loudly.
  def option_id(fields, field_name, value)
    field = fields[field_name] or raise Error, "The project has no #{field_name} field"
    option = field["options"][value]
    raise Error, "#{field_name} has no option #{value.inspect}; choose one of #{field["options"].keys.join(", ")}" unless option

    [ field["id"], option ]
  end

  # Board items that are issues, as
  # { "item_id", "number", "title", "state", "labels", "repository", "Status", "Priority", "Size" }.
  # Pull requests and draft issues are dropped: only issues are triaged.
  def issues(item_nodes)
    item_nodes.filter_map do |item|
      content = item["content"] || {}
      next unless content["__typename"] == "Issue"

      values = item.dig("fieldValues", "nodes").to_a.each_with_object({}) do |value, collected|
        name = value.dig("field", "name")
        collected[name] = value["name"] if name
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
        "Size" => values["Size"]
      }
    end
  end

  def untriaged?(issue)
    issue["state"] == "OPEN" && TRIAGE_FIELDS.any? { |field| issue[field].nil? }
  end

  # The field changes `set` should make. A field that already holds a different
  # value is a maintainer's call and is refused unless `force` is given; setting
  # a field to the value it already has is a no-op.
  def changes(issue, requested, force: false)
    requested.each_with_object({}) do |(field, value), changes|
      next if value.nil? || issue&.fetch(field, nil) == value

      current = issue&.fetch(field, nil)
      if current && !force
        raise Error, "Issue #{issue["number"]} already has #{field} #{current}; pass --force to change it to #{value}"
      end

      changes[field] = value
    end
  end

  def format_table(issues)
    return "Nothing to triage." if issues.empty?

    issues.sort_by { |issue| issue["number"] }.map do |issue|
      columns = [
        issue["number"].to_s.rjust(4),
        (issue["Priority"] || "-").ljust(2),
        (issue["Size"] || "-").ljust(2),
        (issue["Status"] || "-").ljust(11),
        issue["title"]
      ]
      labels = issue["labels"].empty? ? "" : "  [#{issue["labels"].join(", ")}]"
      columns.join("  ") + labels
    end.join("\n")
  end
end
