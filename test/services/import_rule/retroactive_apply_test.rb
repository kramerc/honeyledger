require "test_helper"

class ImportRule::RetroactiveApplyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_account = accounts(:linked_asset) # has sourceable (Simplefin::Account)
    @original_expense = Account.create!(user: @user, name: "Old Groceries", kind: :expense, currency: @currency)
    @new_expense = Account.create!(user: @user, name: "Groceries", kind: :expense, currency: @currency)

    @imported_transaction = Transaction.create!(
      user: @user,
      src_account: @bank_account,
      dest_account: @original_expense,
      amount_minor: 5000,
      currency: @currency,
      description: "GROCERY STORE #123",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_one)
    )

    @rule = ImportRule.create!(
      user: @user,
      account: @new_expense,
      match_pattern: "GROCERY",
      match_type: :contains,
      priority: 10
    )
  end

  test "preview returns changes for matching transactions" do
    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == @imported_transaction.id }
    assert_not_nil matching
    assert_equal @original_expense, matching.old_account
    assert_equal @new_expense, matching.new_account
    assert_equal :expense, matching.direction
  end

  test "preview skips transactions already matching the rule account" do
    @imported_transaction.update!(dest_account: @new_expense)

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "preview skips merged transactions" do
    @imported_transaction.update_columns(merged_into_id: @imported_transaction.id)

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "preview skips split transactions" do
    @imported_transaction.update_columns(split: true)

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "preview skips opening balance transactions" do
    @imported_transaction.update_columns(opening_balance: true)

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "preview skips transactions without sourceable" do
    manual_transaction = Transaction.create!(
      user: @user,
      src_account: @bank_account,
      dest_account: @original_expense,
      amount_minor: 1000,
      currency: @currency,
      description: "GROCERY STORE #456",
      transacted_at: 1.day.ago
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == manual_transaction.id }
  end

  test "preview handles revenue transactions" do
    revenue_account = Account.create!(user: @user, name: "Old Revenue", kind: :revenue, currency: @currency)
    new_revenue = Account.create!(user: @user, name: "Grocery Refund", kind: :revenue, currency: @currency)

    revenue_transaction = Transaction.create!(
      user: @user,
      src_account: revenue_account,
      dest_account: @bank_account,
      amount_minor: 2000,
      currency: @currency,
      description: "PAYROLL DEPOSIT",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_two)
    )

    refund_rule = ImportRule.create!(
      user: @user,
      account: new_revenue,
      match_pattern: "PAYROLL",
      match_type: :contains,
      priority: 5
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == revenue_transaction.id }
    assert_not_nil matching
    assert_equal revenue_account, matching.old_account
    assert_equal new_revenue, matching.new_account
    assert_equal :revenue, matching.direction
  end

  test "apply updates counterpart accounts" do
    service = ImportRule::RetroactiveApply.new(user: @user)
    count = service.apply

    assert count > 0
    @imported_transaction.reload
    assert_equal @new_expense, @imported_transaction.dest_account
    assert_equal @bank_account, @imported_transaction.src_account
  end

  test "apply updates account balances correctly" do
    @bank_account.reset_balance
    @original_expense.reset_balance
    @new_expense.reset_balance

    old_expense_balance_before = @original_expense.reload.balance_minor
    new_expense_balance_before = @new_expense.reload.balance_minor

    service = ImportRule::RetroactiveApply.new(user: @user)
    service.apply

    @original_expense.reload
    @new_expense.reload

    assert_equal old_expense_balance_before - 5000, @original_expense.balance_minor
    assert_equal new_expense_balance_before + 5000, @new_expense.balance_minor
  end

  test "apply updates src_account for revenue transactions" do
    revenue_account = Account.create!(user: @user, name: "Old Salary", kind: :revenue, currency: @currency)
    new_revenue = Account.create!(user: @user, name: "Salary", kind: :revenue, currency: @currency)

    revenue_transaction = Transaction.create!(
      user: @user,
      src_account: revenue_account,
      dest_account: @bank_account,
      amount_minor: 100_000,
      currency: @currency,
      description: "EMPLOYER PAYROLL",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_two)
    )

    ImportRule.create!(
      user: @user,
      account: new_revenue,
      match_pattern: "EMPLOYER PAYROLL",
      match_type: :exact,
      priority: 20
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    service.apply

    revenue_transaction.reload
    assert_equal new_revenue, revenue_transaction.src_account
    assert_equal @bank_account, revenue_transaction.dest_account
  end

  test "apply returns zero when no changes needed" do
    @imported_transaction.update!(dest_account: @new_expense)

    service = ImportRule::RetroactiveApply.new(user: @user)
    count = service.apply

    assert_equal 0, count
  end

  test "highest priority rule wins" do
    low_priority_account = Account.create!(user: @user, name: "Low Priority", kind: :expense, currency: @currency)
    ImportRule.create!(
      user: @user,
      account: low_priority_account,
      match_pattern: "GROCERY",
      match_type: :starts_with,
      priority: 1
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == @imported_transaction.id }
    assert_not_nil matching
    assert_equal @new_expense, matching.new_account
  end

  test "per-rule preview only considers the given rule" do
    other_expense = Account.create!(user: @user, name: "Other Category", kind: :expense, currency: @currency)
    other_rule = ImportRule.create!(
      user: @user,
      account: other_expense,
      match_pattern: "SOMETHING ELSE",
      match_type: :contains,
      priority: 0
    )

    service = ImportRule::RetroactiveApply.new(user: @user, rule: other_rule)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "preview skips split child transactions" do
    @imported_transaction.update_columns(parent_transaction_id: @imported_transaction.id)

    service = ImportRule::RetroactiveApply.new(user: @user)
    changes = service.preview

    assert_not changes.any? { |c| c.transaction.id == @imported_transaction.id }
  end

  test "apply populates errors on ActiveRecord failure" do
    service = ImportRule::RetroactiveApply.new(user: @user)
    service.preview

    # Sabotage a change to trigger a validation error
    service.changes.each do |change|
      change.new_account = change.transaction.src_account
    end

    count = service.apply
    assert_equal 0, count
    assert service.errors.any?
  end

  test "per-rule preview finds matching transactions for the given rule" do
    service = ImportRule::RetroactiveApply.new(user: @user, rule: @rule)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == @imported_transaction.id }
    assert_not_nil matching
    assert_equal @new_expense, matching.new_account
  end

  # --- Balance sheet rules with auto-merge ---

  test "preview includes merge candidate for balance sheet rule" do
    savings = Account.create!(user: @user, name: "Savings", kind: :asset, currency: @currency)
    bs_rule = ImportRule.create!(user: @user, account: savings, match_pattern: "TRANSFER", match_type: :contains, priority: 20)

    transfer_out = Transaction.create!(
      user: @user, src_account: @bank_account, dest_account: @original_expense,
      amount_minor: 5000, currency: @currency, description: "TRANSFER TO SAVINGS",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    # The other side of the transfer (from savings import)
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    other_side = Transaction.create!(
      user: @user, src_account: revenue, dest_account: savings,
      amount_minor: 5000, currency: @currency, description: "TRANSFER FROM CHECKING",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_two)
    )

    service = ImportRule::RetroactiveApply.new(user: @user, rule: bs_rule)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == transfer_out.id }
    assert_not_nil matching
    assert_equal savings, matching.new_account
    assert_equal other_side, matching.merge_candidate
  end

  test "preview has nil merge candidate when no match exists for balance sheet rule" do
    savings = Account.create!(user: @user, name: "Savings", kind: :asset, currency: @currency)
    bs_rule = ImportRule.create!(user: @user, account: savings, match_pattern: "TRANSFER", match_type: :contains, priority: 20)

    transfer_out = Transaction.create!(
      user: @user, src_account: @bank_account, dest_account: @original_expense,
      amount_minor: 5000, currency: @currency, description: "TRANSFER TO SAVINGS",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    service = ImportRule::RetroactiveApply.new(user: @user, rule: bs_rule)
    changes = service.preview

    matching = changes.find { |c| c.transaction.id == transfer_out.id }
    assert_not_nil matching
    assert_nil matching.merge_candidate
  end

  test "apply uses auto-merge for balance sheet rule with merge candidate" do
    savings = Account.create!(user: @user, name: "Savings", kind: :asset, currency: @currency)
    ImportRule.create!(user: @user, account: savings, match_pattern: "TRANSFER", match_type: :contains, priority: 20)

    transfer_out = Transaction.create!(
      user: @user, src_account: @bank_account, dest_account: @original_expense,
      amount_minor: 5000, currency: @currency, description: "TRANSFER TO SAVINGS",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    other_side = Transaction.create!(
      user: @user, src_account: revenue, dest_account: savings,
      amount_minor: 5000, currency: @currency, description: "TRANSFER FROM CHECKING",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_two)
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    service.apply

    transfer_out.reload
    other_side.reload

    # Both originals should be zeroed and merged
    assert_equal 0, transfer_out.amount_minor
    assert_equal 0, other_side.amount_minor
    assert_not_nil transfer_out.merged_into_id
    assert_equal transfer_out.merged_into_id, other_side.merged_into_id

    # Merged transaction should be a transfer
    merged = Transaction.find(transfer_out.merged_into_id)
    assert_equal @bank_account, merged.src_account
    assert_equal savings, merged.dest_account
    assert_equal 5000, merged.amount_minor
  end

  test "apply falls back to account change for balance sheet rule without merge candidate" do
    savings = Account.create!(user: @user, name: "Savings", kind: :asset, currency: @currency)
    ImportRule.create!(user: @user, account: savings, match_pattern: "TRANSFER", match_type: :contains, priority: 20)

    transfer_out = Transaction.create!(
      user: @user, src_account: @bank_account, dest_account: @original_expense,
      amount_minor: 5000, currency: @currency, description: "TRANSFER TO SAVINGS",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    service = ImportRule::RetroactiveApply.new(user: @user)
    service.apply

    transfer_out.reload

    # No merge candidate — rule account applied directly
    assert_equal @bank_account, transfer_out.src_account
    assert_equal savings, transfer_out.dest_account
    assert_equal 5000, transfer_out.amount_minor
    assert_nil transfer_out.merged_into_id
  end
end
