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

  test "defaults direction_overridden to false" do
    row = TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)

    assert_not row.direction_overridden?
  end

  test "records direction_overridden when the importer overrode the direction (#222)" do
    row = TransactionSource::Attach.call(
      transaction: @ledger_transaction, sourceable: @simplefin_transaction,
      direction_overridden: true
    )

    assert row.direction_overridden?
  end

  test "does not rewrite direction_overridden on the idempotent find path (#222)" do
    TransactionSource::Attach.call(transaction: @ledger_transaction, sourceable: @simplefin_transaction)

    row = nil
    assert_no_difference("TransactionSource.count") do
      row = TransactionSource::Attach.call(
        transaction: @ledger_transaction, sourceable: @simplefin_transaction,
        direction_overridden: true
      )
    end

    assert_not row.reload.direction_overridden?,
      "the flag is a historical fact about the first writer's import decision, not a re-derivation"
  end
end
