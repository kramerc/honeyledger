require "test_helper"

class ProjectBoardTest < ActiveSupport::TestCase
  FIELD_NODES = [
    { "id" => "status-field", "name" => "Status", "options" => [ { "id" => "backlog", "name" => "Backlog" } ] },
    { "id" => "priority-field", "name" => "Priority", "options" => [
      { "id" => "p0", "name" => "P0" }, { "id" => "p1", "name" => "P1" }, { "id" => "p2", "name" => "P2" }
    ] },
    { "id" => "size-field", "name" => "Size", "options" => [ { "id" => "xs", "name" => "XS" }, { "id" => "m", "name" => "M" } ] },
    { "id" => "estimate-field", "name" => "Estimate" },
    { "id" => "title-field", "name" => "Title" }
  ].freeze

  def item(id, typename:, number: 1, state: "OPEN", values: {}, labels: [], sub_issues: 0, parent: nil)
    {
      "id" => id,
      "content" => {
        "__typename" => typename,
        "number" => number,
        "title" => "Sample issue #{number}",
        "state" => state,
        "repository" => { "nameWithOwner" => "owner/repo" },
        "labels" => { "nodes" => labels.map { |name| { "name" => name } } },
        "subIssuesSummary" => { "total" => sub_issues },
        "parent" => parent && { "number" => parent }
      },
      "fieldValues" => { "nodes" => [ {} ] + values.map do |field, value|
        { (value.is_a?(Numeric) ? "number" : "name") => value, "field" => { "name" => field } }
      end }
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

  test "looks up any field id by name" do
    assert_equal "estimate-field", ProjectBoard.field_id(FIELD_NODES, "Estimate")
    assert_raises(ProjectBoard::Error) { ProjectBoard.field_id(FIELD_NODES, "Effort") }
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
    assert_nil issue["Estimate"]
  end

  test "reads a whole-number estimate as an integer and keeps a fractional one" do
    issues = ProjectBoard.issues([
      item("item-1", typename: "Issue", number: 1, values: { "Size" => "M", "Estimate" => 3.0 }),
      item("item-2", typename: "Issue", number: 2, values: { "Estimate" => 2.5 })
    ])

    assert_equal 3, issues.first["Estimate"]
    assert_kind_of Integer, issues.first["Estimate"]
    assert_equal 2.5, issues.last["Estimate"]
  end

  test "derives the estimate from the size and skips one already in place" do
    assert_equal({ "XS" => 1, "S" => 2, "M" => 3, "L" => 5, "XL" => 8 }, ProjectBoard::ESTIMATES)
    assert_equal 5, ProjectBoard.estimate_change({ "Estimate" => nil }, "L")
    assert_equal 5, ProjectBoard.estimate_change({ "Estimate" => 13 }, "L")
    assert_nil ProjectBoard.estimate_change({ "Estimate" => 5 }, "L")
    assert_nil ProjectBoard.estimate_change({ "Estimate" => 5 }, nil)
    assert_equal 1, ProjectBoard.estimate_change(nil, "XS")
  end

  test "an estimate that is missing or disagrees with the size is a mismatch" do
    assert ProjectBoard.estimate_mismatch?({ "Size" => "M", "Estimate" => nil })
    assert ProjectBoard.estimate_mismatch?({ "Size" => "M", "Estimate" => 5 })
    assert_not ProjectBoard.estimate_mismatch?({ "Size" => "M", "Estimate" => 3 })
    assert_not ProjectBoard.estimate_mismatch?({ "Size" => nil, "Estimate" => 5 })
  end

  test "an open issue missing priority or size is untriaged; a closed one never is" do
    assert ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => "P1", "Size" => nil })
    assert ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => nil, "Size" => "S" })
    assert ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => "P1", "Size" => "S", "Estimate" => nil })
    assert_not ProjectBoard.untriaged?({ "state" => "OPEN", "Priority" => "P1", "Size" => "S", "Estimate" => 2 })
    assert_not ProjectBoard.untriaged?({ "state" => "CLOSED", "Priority" => nil, "Size" => nil })
  end

  test "changes fills empty fields and skips values already in place" do
    issue = { "number" => 7, "Priority" => "P1", "Size" => nil }

    assert_equal({ "Size" => "M", "Estimate" => 3 }, ProjectBoard.changes(issue, { "Priority" => "P1", "Size" => "M" }))
    assert_equal({}, ProjectBoard.changes(issue, { "Priority" => "P1", "Size" => nil }))
  end

  test "changes refuses to replace an existing value unless forced" do
    issue = { "number" => 7, "Priority" => "P1", "Size" => nil }

    error = assert_raises(ProjectBoard::Error) { ProjectBoard.changes(issue, { "Priority" => "P0" }) }
    assert_includes error.message, "--force"
    assert_equal({ "Priority" => "P0" }, ProjectBoard.changes(issue, { "Priority" => "P0" }, force: true))
  end

  test "changes sets every requested field for an issue not on the board yet" do
    assert_equal({ "Priority" => "P2", "Size" => "XS", "Estimate" => 1 }, ProjectBoard.changes(nil, { "Priority" => "P2", "Size" => "XS" }))
  end

  test "changes corrects a stale estimate without --force, following the size the issue will have" do
    sized = { "number" => 7, "Priority" => "P1", "Size" => "S", "Estimate" => 8 }

    assert_equal({ "Estimate" => 2 }, ProjectBoard.changes(sized, { "Priority" => "P1", "Size" => nil }))
    assert_equal({ "Size" => "L", "Estimate" => 5 }, ProjectBoard.changes(sized, { "Size" => "L" }, force: true))
    assert_equal({}, ProjectBoard.changes(sized.merge("Estimate" => 2), { "Size" => "S" }))
  end

  test "reads the sub-issue count and parent number" do
    parent, child, plain = ProjectBoard.issues([
      item("item-1", typename: "Issue", number: 10, sub_issues: 3),
      item("item-2", typename: "Issue", number: 11, parent: 10),
      item("item-3", typename: "Issue", number: 12)
    ])

    assert_equal [ 3, nil ], parent.values_at("sub_issues", "parent")
    assert_equal [ 0, 10 ], child.values_at("sub_issues", "parent")
    assert ProjectBoard.parent?(parent)
    assert_not ProjectBoard.parent?(child)
    assert_not ProjectBoard.parent?(plain)
    assert_not ProjectBoard.parent?(nil)
  end

  test "a parent's estimate is cleared rather than derived from its size" do
    parent = { "number" => 10, "sub_issues" => 2, "Priority" => "P2", "Size" => "XL", "Estimate" => 8 }

    assert_equal ProjectBoard::CLEAR, ProjectBoard.estimate_change(parent, "XL")
    assert_nil ProjectBoard.estimate_change(parent.merge("Estimate" => nil), "XL")
    assert ProjectBoard.estimate_mismatch?(parent)
    assert_not ProjectBoard.estimate_mismatch?(parent.merge("Estimate" => nil))
  end

  test "a parent needs a priority but no size, and is untriaged while it still has an estimate" do
    parent = { "state" => "OPEN", "sub_issues" => 2, "Priority" => "P2", "Size" => nil, "Estimate" => nil }

    assert_not ProjectBoard.untriaged?(parent)
    assert_not ProjectBoard.untriaged?(parent.merge("Size" => "XL"))
    assert ProjectBoard.untriaged?(parent.merge("Priority" => nil))
    assert ProjectBoard.untriaged?(parent.merge("Size" => "XL", "Estimate" => 8))
  end

  test "changes clears a parent's estimate even when its size is set or unchanged" do
    parent = { "number" => 10, "sub_issues" => 2, "Priority" => "P2", "Size" => "XL", "Estimate" => 8 }

    assert_equal({ "Estimate" => ProjectBoard::CLEAR }, ProjectBoard.changes(parent, { "Priority" => "P2", "Size" => nil }))
    assert_equal({ "Size" => "L", "Estimate" => ProjectBoard::CLEAR }, ProjectBoard.changes(parent, { "Size" => "L" }, force: true))
    assert_equal({}, ProjectBoard.changes(parent.merge("Estimate" => nil), { "Size" => "XL" }))
  end

  test "the table notes how many sub-issues a parent has" do
    parent = { "number" => 10, "title" => "Epic", "labels" => %w[enhancement], "Status" => "Backlog",
               "Priority" => "P2", "Size" => "XL", "Estimate" => 8, "sub_issues" => 4 }

    assert_equal "  10  P2  XL  8!   Backlog      Epic  (4 sub-issues)  [enhancement]", ProjectBoard.format_table([ parent ]).rstrip
  end

  test "formats a table sorted by number with blanks shown as dashes and a stale estimate flagged" do
    issues = [
      { "number" => 12, "title" => "Later", "labels" => [], "Status" => "Ready", "Priority" => "P2", "Size" => "M", "Estimate" => 3 },
      { "number" => 5, "title" => "Stale", "labels" => [], "Status" => "Ready", "Priority" => "P2", "Size" => "M", "Estimate" => nil },
      { "number" => 3, "title" => "Earlier", "labels" => %w[bug], "Status" => nil, "Priority" => nil, "Size" => nil }
    ]

    lines = ProjectBoard.format_table(issues).lines.map(&:rstrip)

    assert_equal "   3  -   -   -    -            Earlier  [bug]", lines.first
    assert_equal "   5  P2  M   -!   Ready        Stale", lines.second
    assert_equal "  12  P2  M   3    Ready        Later", lines.last
    assert_equal "Nothing to triage.", ProjectBoard.format_table([])
  end
end
