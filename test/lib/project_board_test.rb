require "test_helper"

class ProjectBoardTest < ActiveSupport::TestCase
  FIELD_NODES = [
    { "id" => "status-field", "name" => "Status", "options" => [ { "id" => "backlog", "name" => "Backlog" } ] },
    { "id" => "priority-field", "name" => "Priority", "options" => [
      { "id" => "p0", "name" => "P0" }, { "id" => "p1", "name" => "P1" }, { "id" => "p2", "name" => "P2" }
    ] },
    { "id" => "size-field", "name" => "Size", "options" => [ { "id" => "xs", "name" => "XS" }, { "id" => "m", "name" => "M" } ] },
    { "id" => "title-field", "name" => "Title" }
  ].freeze

  def item(id, typename:, number: 1, state: "OPEN", values: {}, labels: [])
    {
      "id" => id,
      "content" => {
        "__typename" => typename,
        "number" => number,
        "title" => "Sample issue #{number}",
        "state" => state,
        "repository" => { "nameWithOwner" => "owner/repo" },
        "labels" => { "nodes" => labels.map { |name| { "name" => name } } }
      },
      "fieldValues" => { "nodes" => [ {} ] + values.map { |field, value| { "name" => value, "field" => { "name" => field } } } }
    }
  end

  test "collects single-select fields with their options in rank order" do
    fields = ProjectBoard.single_select_fields(FIELD_NODES)

    assert_equal %w[Status Priority Size], fields.keys
    assert_equal({ "P0" => "p0", "P1" => "p1", "P2" => "p2" }, fields.dig("Priority", "options"))
    assert_equal %w[P0 P1 P2], fields.dig("Priority", "options").keys
  end

  test "resolves an option name to the field and option ids" do
    fields = ProjectBoard.single_select_fields(FIELD_NODES)

    assert_equal [ "size-field", "m" ], ProjectBoard.option_id(fields, "Size", "M")
  end

  test "rejects an unknown option or field with the valid choices" do
    fields = ProjectBoard.single_select_fields(FIELD_NODES)

    error = assert_raises(ProjectBoard::Error) { ProjectBoard.option_id(fields, "Priority", "P3") }
    assert_includes error.message, "P0, P1, P2"
    assert_raises(ProjectBoard::Error) { ProjectBoard.option_id(fields, "Effort", "M") }
  end

  test "keeps only issues and reads their field values and labels" do
    nodes = [
      item("item-1", typename: "Issue", number: 7, values: { "Status" => "Backlog", "Priority" => "P1" }, labels: %w[bug]),
      item("item-2", typename: "PullRequest", number: 8),
      { "id" => "item-3", "content" => { "__typename" => "DraftIssue" }, "fieldValues" => { "nodes" => [] } }
    ]

    issues = ProjectBoard.issues(nodes)

    assert_equal 1, issues.size
    issue = issues.first
    assert_equal "item-1", issue["item_id"]
    assert_equal 7, issue["number"]
    assert_equal "owner/repo", issue["repository"]
    assert_equal %w[bug], issue["labels"]
    assert_equal "Backlog", issue["Status"]
    assert_equal "P1", issue["Priority"]
    assert_nil issue["Size"]
  end

  test "an open issue missing priority or size is untriaged; a closed one never is" do
    assert ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => "P1", "Size" => nil })
    assert ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => nil, "Size" => "S" })
    assert_not ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => "P1", "Size" => "S" })
    assert_not ProjectBoard.untriaged?({ "state" => "CLOSED", "Priority" => nil, "Size" => nil })
  end

  test "changes fills empty fields and skips values already in place" do
    issue = { "number" => 7, "Priority" => "P1", "Size" => nil }

    assert_equal({ "Size" => "M" }, ProjectBoard.changes(issue, { "Priority" => "P1", "Size" => "M" }))
    assert_equal({}, ProjectBoard.changes(issue, { "Priority" => "P1", "Size" => nil }))
  end

  test "changes refuses to replace an existing value unless forced" do
    issue = { "number" => 7, "Priority" => "P1", "Size" => nil }

    error = assert_raises(ProjectBoard::Error) { ProjectBoard.changes(issue, { "Priority" => "P0" }) }
    assert_includes error.message, "--force"
    assert_equal({ "Priority" => "P0" }, ProjectBoard.changes(issue, { "Priority" => "P0" }, force: true))
  end

  test "changes sets every requested field for an issue not on the board yet" do
    assert_equal({ "Priority" => "P2", "Size" => "XS" }, ProjectBoard.changes(nil, { "Priority" => "P2", "Size" => "XS" }))
  end

  test "formats a table sorted by number with blanks shown as dashes" do
    issues = [
      { "number" => 12, "title" => "Later", "labels" => [], "Status" => "Ready", "Priority" => "P2", "Size" => "M" },
      { "number" => 3, "title" => "Earlier", "labels" => %w[bug], "Status" => nil, "Priority" => nil, "Size" => nil }
    ]

    lines = ProjectBoard.format_table(issues).lines.map(&:rstrip)

    assert_equal "   3  -   -   -            Earlier  [bug]", lines.first
    assert_equal "  12  P2  M   Ready        Later", lines.last
    assert_equal "Nothing to triage.", ProjectBoard.format_table([])
  end
end
