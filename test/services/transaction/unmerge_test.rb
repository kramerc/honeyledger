require "test_helper"

class Transaction::UnmergeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_a = accounts(:asset_account)
    @bank_b = accounts(:linked_asset)

    # Create and merge two transactions
    @expense_account = Account.create!(user: @user, name: "Unmerge Expense", kind: :expense, currency: @currency)
    @revenue_account = Account.create!(user: @user, name: "Unmerge Revenue", kind: :revenue, currency: @currency)

    @withdrawal = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: @expense_account,
      amount_minor: 750, currency: @currency, description: "Original withdrawal",
      transacted_at: 1.day.ago
    )

    @deposit = Transaction.create!(
      user: @user, src_account: @revenue_account, dest_account: @bank_b,
      amount_minor: 750, currency: @currency, description: "Original deposit",
      transacted_at: 1.day.ago
    )

    merger = Transaction::Merge.new(@withdrawal, @deposit, user: @user)
    assert merger.call, "Merge setup failed: #{merger.errors.join(', ')}"
    @merged = merger.merged_transaction
  end

  test "unmerge restores original transactions" do
    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    assert unmerger.call

    assert_equal 2, unmerger.restored_transactions.size

    @withdrawal.reload
    @deposit.reload

    assert_equal 750, @withdrawal.amount_minor
    assert_equal 750, @deposit.amount_minor
    assert_nil @withdrawal.merged_into_id
    assert_nil @deposit.merged_into_id
  end

  test "unmerge destroys the merged transfer" do
    merged_id = @merged.id
    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    unmerger.call

    assert_nil Transaction.find_by(id: merged_id)
  end

  test "unmerge corrects account balances" do
    @bank_a.reset_balance
    @bank_b.reset_balance

    bank_a_before = @bank_a.reload.balance_minor
    bank_b_before = @bank_b.reload.balance_minor

    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    unmerger.call

    @bank_a.reload
    @bank_b.reload

    # Balances should remain the same — same net effect
    assert_equal bank_a_before, @bank_a.balance_minor
    assert_equal bank_b_before, @bank_b.balance_minor
  end

  test "unmerge restores original account associations" do
    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    unmerger.call

    @withdrawal.reload
    @deposit.reload

    assert_equal @bank_a, @withdrawal.src_account
    assert_equal @expense_account, @withdrawal.dest_account
    assert_equal @revenue_account, @deposit.src_account
    assert_equal @bank_b, @deposit.dest_account
  end

  test "restored transactions appear in unmerged scope" do
    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    unmerger.call

    unmerged = @user.transactions.unmerged
    assert_includes unmerged, @withdrawal.reload
    assert_includes unmerged, @deposit.reload
  end

  test "rejects transaction without merged sources" do
    plain = Transaction.create!(
      user: @user, src_account: @bank_a, dest_account: @expense_account,
      amount_minor: 100, currency: @currency, description: "Plain",
      transacted_at: Time.current
    )

    unmerger = Transaction::Unmerge.new(plain, user: @user)
    assert_not unmerger.call
    assert_includes unmerger.errors, "Transaction has no merged sources to restore"
  end

  test "rejects other user's transaction" do
    other_user = users(:two)
    unmerger = Transaction::Unmerge.new(@merged, user: other_user)
    assert_not unmerger.call
    assert_includes unmerger.errors, "Transaction must belong to you"
  end

  test "returns false with error when RecordInvalid is raised" do
    # Force a RecordInvalid by making one of the originals invalid before unmerge
    @withdrawal.update_columns(src_account_id: @withdrawal.dest_account_id)

    unmerger = Transaction::Unmerge.new(@merged, user: @user)
    assert_not unmerger.call
    assert unmerger.errors.any?
  end
end
