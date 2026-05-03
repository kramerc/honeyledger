require "test_helper"

class TransactionSourceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @ledger_account = accounts(:linked_asset)
    @counterpart = accounts(:expense_account)
    @simplefin_account = @ledger_account.account_sources.first.sourceable
    @simplefin_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "ts_test_1",
      amount: "-12.50",
      description: "Test Coffee",
      transacted_at: 1.day.ago,
      posted: 1.day.ago
    )
    @ledger_transaction = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1250, currency: @currency, description: "Test Coffee",
      transacted_at: 1.day.ago
    )
  end

  test "associations resolve back to the ledger transaction and the source" do
    join = TransactionSource.create!(
      ledger_transaction: @ledger_transaction,
      sourceable: @simplefin_transaction
    )

    assert_equal @ledger_transaction, join.ledger_transaction
    assert_equal @simplefin_transaction, join.sourceable
  end

  test "DB unique index on (sourceable_type, sourceable_id) blocks a second row" do
    TransactionSource.create!(
      ledger_transaction: @ledger_transaction,
      sourceable: @simplefin_transaction
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      other_ledger = Transaction.create!(
        user: @user, src_account: @ledger_account, dest_account: @counterpart,
        amount_minor: 1250, currency: @currency, description: "Test Coffee",
        transacted_at: 1.day.ago
      )
      TransactionSource.create!(
        ledger_transaction: other_ledger,
        sourceable: @simplefin_transaction
      )
    end
  end

  test "ledger_transactions through-association on the aggregator side returns linked rows" do
    TransactionSource.create!(
      ledger_transaction: @ledger_transaction,
      sourceable: @simplefin_transaction
    )

    assert_includes @simplefin_transaction.ledger_transactions, @ledger_transaction
  end
end
