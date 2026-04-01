require "test_helper"

class Transaction::MergeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_a = accounts(:asset_account)
    @bank_b = accounts(:linked_asset)

    # Simulate two imported transactions (both sides of a transfer)
    @expense_account = Account.create!(user: @user, name: "Coffee Shop", kind: :expense, currency: @currency)
    @revenue_account = Account.create!(user: @user, name: "Coffee Shop", kind: :revenue, currency: @currency)

    @withdrawal = Transaction.create!(
      user: @user,
      src_account: @bank_a,
      dest_account: @expense_account,
      amount_minor: 500,
      currency: @currency,
      description: "Coffee Shop",
      transacted_at: 1.day.ago
    )

    @deposit = Transaction.create!(
      user: @user,
      src_account: @revenue_account,
      dest_account: @bank_b,
      amount_minor: 500,
      currency: @currency,
      description: "Coffee Shop",
      transacted_at: 1.day.ago
    )
  end

  test "merges two transactions into a transfer" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)

    assert merger.call
    assert_not_nil merger.merged_transaction

    merged = merger.merged_transaction
    assert_equal @bank_a, merged.src_account
    assert_equal @bank_b, merged.dest_account
    assert_equal 500, merged.amount_minor
    assert_equal @currency, merged.currency
    assert_nil merged.merged_into_id
  end

  test "sets merged_into_id on both originals" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    @withdrawal.reload
    @deposit.reload

    assert_equal merger.merged_transaction.id, @withdrawal.merged_into_id
    assert_equal merger.merged_transaction.id, @deposit.merged_into_id
  end

  test "zeroes out original amounts" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    @withdrawal.reload
    @deposit.reload

    assert_equal 0, @withdrawal.amount_minor
    assert_equal 0, @deposit.amount_minor
  end

  test "corrects account balances" do
    @bank_a.reset_balance
    @bank_b.reset_balance
    @expense_account.reset_balance
    @revenue_account.reset_balance

    bank_a_before = @bank_a.reload.balance_minor
    bank_b_before = @bank_b.reload.balance_minor

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    @bank_a.reload
    @bank_b.reload

    # Net effect should be: bank_a decreased by 500, bank_b increased by 500
    # Before merge: bank_a had -500 (from withdrawal), bank_b had +500 (from deposit)
    # The merge zeroes those out, then creates a new transfer with the same effect
    assert_equal bank_a_before, @bank_a.balance_minor
    assert_equal bank_b_before, @bank_b.balance_minor
  end

  test "preserves expense and revenue accounts after merge" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    # Accounts still exist (merged originals reference them)
    assert_not_nil Account.find_by(id: @expense_account.id)
    assert_not_nil Account.find_by(id: @revenue_account.id)
  end

  test "uses provided description override" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user, description: "Transfer to savings")
    merger.call

    assert_equal "Transfer to savings", merger.merged_transaction.description
  end

  test "uses provided transacted_at override" do
    custom_time = 3.days.ago.beginning_of_minute
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user, transacted_at: custom_time)
    merger.call

    assert_equal custom_time, merger.merged_transaction.transacted_at
  end

  test "works regardless of argument order" do
    # Pass deposit first, withdrawal second
    merger = Transaction::Merge.new(@deposit, @withdrawal, user: @user)

    assert merger.call

    merged = merger.merged_transaction
    assert_equal @bank_a, merged.src_account
    assert_equal @bank_b, merged.dest_account
  end

  test "rejects mismatched amounts" do
    @deposit.update_columns(amount_minor: 999)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Amounts must match"
  end

  test "rejects mismatched currencies" do
    eur = currencies(:eur)
    @deposit.update_columns(currency_id: eur.id)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Currencies must match"
  end

  test "rejects when neither has balance-sheet src" do
    # Both go from revenue/expense to balance-sheet (no balance-sheet src)
    t1 = Transaction.create!(user: @user, src_account: @revenue_account, dest_account: @bank_a,
                             amount_minor: 100, currency: @currency, transacted_at: Time.current)
    t2 = Transaction.create!(user: @user, src_account: @revenue_account, dest_account: @bank_b,
                             amount_minor: 100, currency: @currency, transacted_at: Time.current)

    merger = Transaction::Merge.new(t1, t2, user: @user)
    assert_not merger.call
    assert merger.errors.any? { |e| e.include?("bank account") }
  end

  test "rejects opening balance transactions" do
    @withdrawal.update_columns(opening_balance: true)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Opening balance transactions cannot be merged"
  end

  test "rejects split transactions" do
    @withdrawal.update_columns(split: true)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Split transactions cannot be merged"
  end

  test "rejects FX transactions" do
    @withdrawal.update_columns(fx_amount_minor: 400, fx_currency_id: currencies(:eur).id)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Foreign exchange transactions cannot be merged"
  end

  test "rejects transactions that are already transfers" do
    # Both sides balance-sheet = already a transfer
    transfer = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, description: "Transfer",
      transacted_at: 1.day.ago
    )

    merger = Transaction::Merge.new(transfer, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Transactions that are already transfers cannot be merged"
  end

  test "rejects transactions that are the result of a merge" do
    # Merge first, then try to merge the result again
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call
    merged = merger.merged_transaction

    other_expense = Account.create!(user: @user, name: "Other Expense", kind: :expense, currency: @currency)
    other_withdrawal = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: other_expense,
      amount_minor: merged.amount_minor, currency: @currency, description: "Other",
      transacted_at: 1.day.ago
    )

    merger2 = Transaction::Merge.new(merged, other_withdrawal, user: @user)
    assert_not merger2.call
    assert_includes merger2.errors, "Transactions that are the result of a merge cannot be merged again"
  end

  test "rejects already merged transactions" do
    # Create a dummy merged target
    target = Transaction.create!(user: @user, src_account: @bank_a, dest_account: @bank_b,
                                 amount_minor: 500, currency: @currency, transacted_at: Time.current)
    @withdrawal.update_columns(merged_into_id: target.id)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Already merged transactions cannot be merged again"
  end

  test "rejects transactions belonging to different user" do
    other_user = users(:two)

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: other_user)
    assert_not merger.call
    assert_includes merger.errors, "Both transactions must belong to you"
  end

  test "rejects when both real accounts are the same" do
    # Withdrawal: bank_a → expense, Deposit: revenue → bank_a (same real account on both sides)
    deposit_same = Transaction.create!(
      user: @user, src_account: @revenue_account, dest_account: @bank_a,
      amount_minor: 500, currency: @currency, description: "Same bank",
      transacted_at: 1.day.ago
    )

    merger = Transaction::Merge.new(@withdrawal, deposit_same, user: @user)
    assert_not merger.call
    assert_includes merger.errors, "Source and destination accounts cannot be the same"
  end

  test "returns false with error when RecordInvalid is raised" do
    # Stub create! to raise RecordInvalid inside the transaction block
    Transaction.stub(:create!, ->(_attrs) { raise ActiveRecord::RecordInvalid.new(Transaction.new) }) do
      merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
      assert_not merger.call
      assert merger.errors.any?
    end
  end

  test "unmerged scope excludes merged transactions" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    unmerged = @user.transactions.unmerged
    assert_not_includes unmerged, @withdrawal.reload
    assert_not_includes unmerged, @deposit.reload
    assert_includes unmerged, merger.merged_transaction
  end

  test "merged_sources association returns originals" do
    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    merger.call

    merged = merger.merged_transaction
    assert_equal 2, merged.merged_sources.count
    assert_includes merged.merged_sources, @withdrawal.reload
    assert_includes merged.merged_sources, @deposit.reload
  end
end
