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

  test "invalid with asset account" do
    rule = ImportRule.new(user: @user, account: @asset_account, match_pattern: "Test")
    assert_not rule.valid?
    assert_includes rule.errors[:account], "must be an expense or revenue account"
  end

  test "valid with expense account" do
    rule = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "valid with revenue account" do
    rule = ImportRule.new(user: @user, account: @revenue_account, match_pattern: "Test")
    assert rule.valid?
  end

  test "enforces uniqueness of pattern and match_type per user" do
    ImportRule.create!(user: @user, account: @expense_account, match_pattern: "Duplicate", match_type: :contains)
    duplicate = ImportRule.new(user: @user, account: @expense_account, match_pattern: "Duplicate", match_type: :contains)
    assert_not duplicate.valid?
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

  # Auto-creation on account rename

  test "renaming expense account creates exact-match rule for old name" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "AMZN*12345", kind: :expense)

    assert_difference "ImportRule.count", 1 do
      account.update!(name: "Amazon")
    end

    rule = account.import_rules.last
    assert_equal "AMZN*12345", rule.match_pattern
    assert_equal "exact", rule.match_type
    assert_equal @user, rule.user
  end

  test "renaming revenue account creates exact-match rule for old name" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "ACME CORP PAYROLL", kind: :revenue)

    assert_difference "ImportRule.count", 1 do
      account.update!(name: "Salary")
    end

    rule = account.import_rules.last
    assert_equal "ACME CORP PAYROLL", rule.match_pattern
  end

  test "renaming asset account does not create rule" do
    assert_no_difference "ImportRule.count" do
      @asset_account.update!(name: "New Name")
    end
  end

  test "renaming expense account twice does not duplicate rule" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "Original", kind: :expense)
    account.update!(name: "Renamed Once")

    assert_no_difference "ImportRule.count" do
      account.update!(name: "Renamed Once") # no actual change
    end

    assert_difference "ImportRule.count", 1 do
      account.update!(name: "Renamed Twice")
    end
  end

  test "renaming back to old name cleans up redundant rule" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "AMZN*12345", kind: :expense)
    account.update!(name: "Amazon")

    assert_equal 1, account.import_rules.count
    assert_equal "AMZN*12345", account.import_rules.first.match_pattern

    # Rename back — "Amazon" rule is created, "AMZN*12345" rule is removed (matches new name)
    account.update!(name: "AMZN*12345")

    account.reload
    assert_equal 1, account.import_rules.count
    assert_equal "Amazon", account.import_rules.first.match_pattern
  end

  test "updating non-name attributes does not create rule" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "Test Expense", kind: :expense)

    assert_no_difference "ImportRule.count" do
      account.update!(balance_minor: 5000)
    end
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
