require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # Provide a controllable request for helpers that call request.path / current_page?
  def request
    @mock_request ||= ActionDispatch::TestRequest.create
  end

  def with_path(path)
    request.env["PATH_INFO"] = path
  end

  setup do
    with_path("/")
  end

  # nav_link_to

  test "nav_link_to renders a link with the given name and url" do
    result = nav_link_to("Home", "/")
    assert_match(/Home/, result)
    assert_match(/href="\//, result)
  end

  test "nav_link_to has active class when on the exact page" do
    with_path("/categories")
    result = nav_link_to("Categories", "/categories")
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to has no active class when on a different page" do
    with_path("/currencies")
    result = nav_link_to("Categories", "/categories")
    assert_no_match(/\bactive\b/, result)
  end

  test "nav_link_to does not mark a prefix path active without :prefix option" do
    with_path("/categories/new")
    result = nav_link_to("Categories", "/categories")
    assert_no_match(/\bactive\b/, result)
  end

  # nav_link_to with :prefix

  test "nav_link_to with :prefix is active on exact match" do
    with_path("/accounts")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is active on sub-path" do
    with_path("/accounts/1/transactions")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is not active on a path sharing only a string prefix" do
    with_path("/accounts_extra")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_no_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is not active on an unrelated path" do
    with_path("/categories")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_no_match(/\bactive\b/, result)
  end

  # nav_link_to class merging

  test "nav_link_to preserves existing classes when adding active" do
    with_path("/accounts")
    result = nav_link_to("Accounts", "/accounts", class: "nav-item", active: :prefix)
    assert_match(/\bnav-item\b/, result)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to passes through extra html options" do
    result = nav_link_to("Logout", "/logout", data: { turbo_method: :delete })
    assert_match(/data-turbo-method="delete"/, result)
  end

  # source_badge_label

  test "source_badge_label labels SimpleFIN sources" do
    assert_equal "SimpleFIN", source_badge_label(simplefin_accounts(:linked_one))
  end

  test "source_badge_label labels Lunch Flow sources" do
    assert_equal "Lunch Flow", source_badge_label(lunchflow_accounts(:linked_one))
  end

  test "source_badge_label labels CSV sources as CSV (not Csv::Transaction)" do
    csv_transaction = Csv::Transaction.new
    assert_equal "CSV", source_badge_label(csv_transaction)
  end

  test "source_badge_label falls back to the class name for unknown sourceable types" do
    # Currency isn't a registered aggregator type but stands in for any future
    # source class (OFX, etc.) so the fallback can't silently render empty.
    assert_equal "Currency", source_badge_label(currencies(:usd))
  end

  # source_badge_modifier

  test "source_badge_modifier returns the SimpleFIN modifier class" do
    assert_equal "source-badge--simplefin", source_badge_modifier(simplefin_accounts(:linked_one))
  end

  test "source_badge_modifier returns the Lunch Flow modifier class" do
    assert_equal "source-badge--lunchflow", source_badge_modifier(lunchflow_accounts(:linked_one))
  end

  test "source_badge_modifier returns the CSV modifier class" do
    assert_equal "source-badge--csv", source_badge_modifier(Csv::Transaction.new)
  end

  test "source_badge_modifier returns nil for unknown sourceable types" do
    assert_nil source_badge_modifier(currencies(:usd))
  end

  # transaction_source_badges

  test "transaction_source_badges renders one styled span per source with aggregator modifiers" do
    fake_source = Struct.new(:sourceable)
    sources = [
      fake_source.new(simplefin_accounts(:linked_one)),
      fake_source.new(lunchflow_accounts(:linked_one))
    ]

    html = transaction_source_badges(sources)

    assert_match(/<span class="source-badge source-badge--simplefin">SimpleFIN<\/span>/, html)
    assert_match(/<span class="source-badge source-badge--lunchflow">Lunch Flow<\/span>/, html)
  end

  test "transaction_source_badges collapses sources sharing a label into one chip" do
    fake_source = Struct.new(:sourceable)
    sources = [
      fake_source.new(Csv::Transaction.new),
      fake_source.new(Csv::Transaction.new)
    ]

    html = transaction_source_badges(sources)

    assert_equal 1, html.scan(/<span class="source-badge source-badge--csv">CSV<\/span>/).size
  end

  test "transaction_source_badges keeps distinct labels while collapsing repeats" do
    fake_source = Struct.new(:sourceable)
    sources = [
      fake_source.new(Csv::Transaction.new),
      fake_source.new(simplefin_accounts(:linked_one)),
      fake_source.new(Csv::Transaction.new)
    ]

    html = transaction_source_badges(sources)

    assert_equal 1, html.scan(/source-badge--csv">CSV<\/span>/).size
    assert_equal 1, html.scan(/source-badge--simplefin">SimpleFIN<\/span>/).size
  end
end
