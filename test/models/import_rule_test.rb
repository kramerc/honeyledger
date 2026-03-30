require "test_helper"

class ImportRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @expense_account = accounts(:expense_account)
    @revenue_account = accounts(:revenue_account)
    @asset_account = accounts(:asset_account)
  end

  test "valid with required attributes" do
    rule = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "invalid without match_pattern" do
    rule = ImportRule.new(user: @user, account: @expense_account, match_pattern: nil)
    assert_not rule.valid?
    assert_includes rule.errors[:match_pattern], "can't be blank"
  end

  test "valid with asset account" do
    rule = ImportRule.new(user: @user, account: @asset_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "valid with liability account" do
    liability_account = Account.create!(user: @user, currency: currencies(:usd), name: "Credit Card", kind: :liability)
    rule = ImportRule.new(user: @user, account: liability_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "valid with equity account" do
    equity_account = Account.create!(user: @user, currency: currencies(:usd), name: "Equity", kind: :equity)
    rule = ImportRule.new(user: @user, account: equity_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "invalid with virtual account" do
    virtual_account = Account.opening_balance_for(user: @user, kind: :revenue)
    rule = ImportRule.new(user: @user, account: virtual_account, match_pattern: "Test")
    assert_not rule.valid?
    assert_includes rule.errors[:account], "must not be a virtual account"
  end

  test "valid with expense account" do
    rule = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "valid with revenue account" do
    rule = ImportRule.new(user: @user, account: @revenue_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "invalid with another users account" do
    other_account = Account.create!(user: users(:two), currency: currencies(:usd), name: "Other Expense", kind: :expense)
    rule = ImportRule.new(user: @user, account: other_account, match_pattern: "Test")
    assert_not rule.valid?
    assert_includes rule.errors[:account], "must belong to you"
  end

  test "enforces uniqueness of pattern and match_type per user" do
    ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Duplicate", match_type: :contains)
    duplicate = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Duplicate", match_type: :contains)
    assert_not duplicate.valid?
  end

  test "enforces case-insensitive uniqueness" do
    ImportRule.create!(user: @user, account: @expense_account, match_pattern: "amazon", match_type: :contains)
    duplicate = ImportRule.new(user: @user, account: @expense_account, match_pattern: "AMAZON", match_type: :contains)
    assert_not duplicate.valid?
  end

  test "strips whitespace from match_pattern" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "  coffee  ", match_type: :contains)
    assert_equal "coffee", rule.match_pattern
  end

  test "allows same pattern with different match_type" do
    ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Same", match_type: :contains)
    different_type = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Same", match_type: :exact)
    assert different_type.valid?
  end

  # for_description scope

  test "contains match" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "AMZN", match_type: :contains)
    assert_includes ImportRule.for_description("AMZN*12345 Order"), rule
    assert_includes ImportRule.for_description("Buy at AMZN store"), rule
    assert_empty ImportRule.for_description("Amazon.com")
  end

  test "exact match" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Starbucks", match_type: :exact)
    assert_includes ImportRule.for_description("Starbucks"), rule
    assert_empty ImportRule.for_description("Starbucks Coffee")
  end

  test "starts_with match" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "SQ *", match_type: :starts_with)
    assert_includes ImportRule.for_description("SQ * Coffee Shop"), rule
    assert_empty ImportRule.for_description("Buy at SQ * store")
  end

  test "ends_with match" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Inc.", match_type: :ends_with)
    assert_includes ImportRule.for_description("Amazon Inc."), rule
    assert_empty ImportRule.for_description("Inc. Amazon")
  end

  test "pattern with percent is treated literally" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "100%", match_type: :contains)
    assert_includes ImportRule.for_description("Got 100% off"), rule
    assert_empty ImportRule.for_description("Got 1000 off")
  end

  test "pattern with underscore is treated literally" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "item_1", match_type: :exact)
    assert_includes ImportRule.for_description("item_1"), rule
    assert_empty ImportRule.for_description("itemX1")
  end

  test "pattern with backslash is treated literally" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "dir\\file", match_type: :contains)
    assert_includes ImportRule.for_description("in dir\\file path"), rule
    assert_empty ImportRule.for_description("in dir file path")
  end

  test "matching is case-insensitive" do
    rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "amazon", match_type: :contains)
    assert_includes ImportRule.for_description("AMAZON.COM"), rule
    assert_includes ImportRule.for_description("Amazon Store"), rule
  end

  test "priority ordering" do
    low = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Coffee", match_type: :contains, priority: 1)
    high = ImportRule.create!(user: @user, account: @revenue_account, match_pattern: "Coffee Shop", match_type: :contains, priority: 10)

    results = ImportRule.for_description("Coffee Shop Downtown")
    assert_equal high, results.first
    assert_equal low, results.second
  end

  # for_kind scope

  test "for_kind filters by account kind" do
    expense_rule = ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Test Expense", match_type: :exact)
    revenue_rule = ImportRule.create!(user: @user, account: @revenue_account, match_pattern: "Test Revenue", match_type: :exact)

    expense_results = ImportRule.for_kind(:expense)
    assert_includes expense_results, expense_rule
    assert_not_includes expense_results, revenue_rule

    revenue_results = ImportRule.for_kind(:revenue)
    assert_includes revenue_results, revenue_rule
    assert_not_includes revenue_results, expense_rule
  end
end
