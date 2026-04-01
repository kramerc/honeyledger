require "test_helper"

class Transaction::AutoMergeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_a = accounts(:asset_account)
    @bank_b = accounts(:linked_asset)
  end

  # --- merge_with_counterpart (two expense/revenue transactions merged via Transaction::Merge) ---

  test "merges two expense/revenue transactions when rule_account matches the other bank" do
    # Imported from bank_b (no rule): revenue → bank_b
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    duplicate = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    # Imported from bank_a (BS rule skipped): bank_a → expense
    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    duplicate.reload

    assert_equal 0, transaction.amount_minor
    assert_equal 0, duplicate.amount_minor
    assert_not_nil transaction.merged_into_id
    assert_equal transaction.merged_into_id, duplicate.merged_into_id

    merged = Transaction.find(transaction.merged_into_id)
    assert_equal @bank_a, merged.src_account
    assert_equal @bank_b, merged.dest_account
    assert_equal 500, merged.amount_minor
  end

  test "works regardless of which side imports first" do
    # Import from bank_a first (BS rule skipped): bank_a → expense
    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    first_import = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    # No match yet — falls back to apply_rule_account
    Transaction::AutoMerge.call(first_import, rule_account: @bank_b)
    first_import.reload
    assert_equal @bank_b, first_import.dest_account # Now a BS→BS transfer

    # Import from bank_b later (no rule): revenue → bank_b
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    second_import = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 1.day.ago
    )

    # absorb_into_existing_transfer: finds the BS→BS transfer from first import
    Transaction::AutoMerge.call(second_import)

    second_import.reload
    first_import.reload

    assert_equal 0, second_import.amount_minor
    assert_equal 0, first_import.amount_minor

    merged = Transaction.find(second_import.merged_into_id)
    assert_equal @bank_a, merged.src_account
    assert_equal @bank_b, merged.dest_account
    assert_equal 500, merged.amount_minor
  end

  # --- apply_rule_account fallback ---

  test "applies rule account when no merge candidate exists" do
    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    assert_no_difference "Transaction.count" do
      Transaction::AutoMerge.call(transaction, rule_account: @bank_b)
    end

    transaction.reload
    assert_equal @bank_a, transaction.src_account
    assert_equal @bank_b, transaction.dest_account
    assert_equal 500, transaction.amount_minor
  end

  test "applies rule account on positive amount (changes src)" do
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_a)

    transaction.reload
    assert_equal @bank_a, transaction.src_account
    assert_equal @bank_b, transaction.dest_account
  end

  # --- absorb_into_existing_transfer ---

  test "absorbs duplicate into existing BS-to-BS transfer" do
    # Existing transfer (created by earlier import with rule applied)
    transfer = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer",
      transacted_at: 2.days.ago
    )

    # Duplicate from other bank (no rule)
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    duplicate = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 1.day.ago
    )

    Transaction::AutoMerge.call(duplicate)

    duplicate.reload
    transfer.reload

    assert_equal 0, duplicate.amount_minor
    assert_equal 0, transfer.amount_minor
    assert_equal duplicate.merged_into_id, transfer.merged_into_id

    merged = Transaction.find(duplicate.merged_into_id)
    assert_equal @bank_a, merged.src_account
    assert_equal @bank_b, merged.dest_account
    assert_equal 500, merged.amount_minor
  end

  # --- no-op cases ---

  test "does not merge when no rule_account and no existing transfer" do
    expense = Account.create!(user: @user, name: "Coffee Shop", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Coffee",
      transacted_at: 2.days.ago
    )

    assert_no_difference "Transaction.count" do
      Transaction::AutoMerge.call(transaction)
    end

    transaction.reload
    assert_equal 500, transaction.amount_minor
    assert_nil transaction.merged_into_id
  end

  test "does not merge when amounts differ" do
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    _other = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 999, currency: @currency, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    # Falls back to apply_rule_account since no match
    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    assert_equal @bank_b, transaction.dest_account
    assert_equal 500, transaction.amount_minor
    assert_nil transaction.merged_into_id
  end

  test "does not merge when currencies differ" do
    eur = currencies(:eur)
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: eur)
    _other = Transaction.create!(
      user: @user, src_account: revenue, dest_account: accounts(:eur_asset_account),
      amount_minor: 500, currency: eur, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    assert_equal @bank_b, transaction.dest_account # Fell back to apply_rule_account
    assert_nil transaction.merged_into_id
  end

  test "does not merge when dates are more than 7 days apart" do
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    _other = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 15.days.ago
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    assert_equal @bank_b, transaction.dest_account # Fell back to apply_rule_account
    assert_nil transaction.merged_into_id
  end

  test "does not merge when multiple candidates exist" do
    revenue_1 = Account.create!(user: @user, name: "Transfer In 1", kind: :revenue, currency: @currency)
    revenue_2 = Account.create!(user: @user, name: "Transfer In 2", kind: :revenue, currency: @currency)

    Transaction.create!(
      user: @user, src_account: revenue_1, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Dup 1",
      transacted_at: 2.days.ago
    )

    Transaction.create!(
      user: @user, src_account: revenue_2, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Dup 2",
      transacted_at: 2.days.ago
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    assert_equal @bank_b, transaction.dest_account # Fell back to apply_rule_account
    assert_nil transaction.merged_into_id
  end

  test "does not merge opening balance transactions" do
    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Opening",
      transacted_at: 2.days.ago, opening_balance: true
    )

    assert_no_difference "Transaction.count" do
      Transaction::AutoMerge.call(transaction, rule_account: @bank_b)
    end

    transaction.reload
    assert_equal expense, transaction.dest_account # Not changed
  end

  test "skips candidates that are already merge results" do
    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    merge_result = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    # Make merge_result look like a merge result by adding a merged source
    expense = Account.create!(user: @user, name: "Some Expense", kind: :expense, currency: @currency)
    Transaction.create!(
      user: @user, src_account: @bank_b, dest_account: expense,
      amount_minor: 0, currency: @currency, description: "Zeroed",
      transacted_at: 2.days.ago, merged_into: merge_result
    )

    expense2 = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense2,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    transaction.reload
    assert_equal @bank_b, transaction.dest_account # Fell back to apply_rule_account
    assert_nil transaction.merged_into_id
  end

  test "corrects account balances after merge_with_counterpart" do
    @bank_a.reset_balance
    @bank_b.reset_balance

    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: 2.days.ago
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: 2.days.ago
    )

    # Before: bank_a -500 (withdrawal to expense), bank_b +500 (deposit from revenue)
    @bank_a.reload
    @bank_b.reload
    bank_a_before = @bank_a.balance_minor
    bank_b_before = @bank_b.balance_minor

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    @bank_a.reload
    @bank_b.reload

    # After merge: net effect unchanged (bank_a -500, bank_b +500)
    assert_equal bank_a_before, @bank_a.balance_minor
    assert_equal bank_b_before, @bank_b.balance_minor
  end

  test "uses earliest transacted_at for merged transaction" do
    earlier = 5.days.ago
    later = 2.days.ago

    revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
    Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer In",
      transacted_at: earlier
    )

    expense = Account.create!(user: @user, name: "Transfer Out", kind: :expense, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense,
      amount_minor: 500, currency: @currency, description: "Transfer Out",
      transacted_at: later
    )

    Transaction::AutoMerge.call(transaction, rule_account: @bank_b)

    merged = Transaction.find(transaction.reload.merged_into_id)
    assert_equal earlier.to_i, merged.transacted_at.to_i
  end

  test "does not merge non-transfer with non-transfer when no rule_account" do
    expense_1 = Account.create!(user: @user, name: "Expense 1", kind: :expense, currency: @currency)
    expense_2 = Account.create!(user: @user, name: "Expense 2", kind: :expense, currency: @currency)

    Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense_1,
      amount_minor: 500, currency: @currency, description: "Expense 1",
      transacted_at: 2.days.ago
    )

    t2 = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: expense_2,
      amount_minor: 500, currency: @currency, description: "Expense 2",
      transacted_at: 2.days.ago
    )

    assert_no_difference "Transaction.count" do
      Transaction::AutoMerge.call(t2)
    end
  end
end
