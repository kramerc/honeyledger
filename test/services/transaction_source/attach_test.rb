require "test_helper"

class TransactionSource::AttachTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @ledger_account = accounts(:linked_asset)
    @counterpart = accounts(:expense_account)
    @simplefin_account = @ledger_account.account_sources.first.sourceable
    @simplefin_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "attach_test_2",
      amount: "-7.25",
      description: "Attach test",
      transacted_at: 1.day.ago,
      posted: 1.day.ago
    )
    @ledger_transaction = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 725, currency: @currency, description: "Attach test",
      transacted_at: 1.day.ago
    )
  end

  test "creates a join row when none exists" do
    assert_difference("TransactionSource.count", 1) do
      TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)
    end
  end

  test "is idempotent on the (sourceable_type, sourceable_id) key" do
    TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)

    assert_no_difference("TransactionSource.count") do
      TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)
    end
  end

  test "raises if the same sourceable is already attached to a different ledger transaction" do
    TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)

    other_ledger = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 725, currency: @currency, description: "Attach test",
      transacted_at: 1.day.ago
    )

    assert_raises(TransactionSource::Attach::MismatchedTransaction) do
      TransactionSource::Attach.call(transaction: other_ledger, sourceable: @simplefin_transaction)
    end
  end
end
