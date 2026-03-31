require "test_helper"

class Lunchflow::TransactionImportJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)

    # Clear any aggregator transactions that would be imported from fixtures (linked via Account.sourceable)
    linked_lf_ids = Account.where(sourceable_type: "Lunchflow::Account").where.not(sourceable_id: nil).pluck(:sourceable_id)
    Lunchflow::Transaction.where(account_id: linked_lf_ids).destroy_all
  end

  test "imports expense transaction (negative amount)" do
    lf_account, lf_bank_account = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_expense_1",
      amount: "-50.00",
      currency: "USD",
      description: "Coffee Shop",
      merchant: "Starbucks",
      pending: false,
      date: 2.days.ago.to_date
    )

    assert_difference "Transaction.count", 1 do
      Lunchflow::TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal lf_bank_account, transaction.src_account
    assert_equal "Starbucks", transaction.description
    assert_equal "expense", transaction.dest_account.kind
    assert_equal 5000, transaction.amount_minor
    assert_not_nil transaction.cleared_at
  end

  test "imports revenue transaction (positive amount)" do
    lf_account, lf_bank_account = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_revenue_1",
      amount: "2500.00",
      currency: "USD",
      description: "Salary",
      merchant: nil,
      pending: false,
      date: 3.days.ago.to_date
    )

    assert_difference "Transaction.count", 1 do
      Lunchflow::TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal lf_bank_account, transaction.dest_account
    assert_equal "Salary", transaction.description
    assert_equal "revenue", transaction.src_account.kind
    assert_equal 250000, transaction.amount_minor
  end

  test "uses merchant over description" do
    lf_account, _ = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_merchant_1",
      amount: "-25.00",
      currency: "USD",
      description: "POS DEBIT 12345",
      merchant: "Whole Foods",
      pending: false,
      date: 1.day.ago.to_date
    )

    Lunchflow::TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_equal "Whole Foods", transaction.description
  end

  test "pending transaction has nil cleared_at" do
    lf_account, _ = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_pending_1",
      amount: "-15.00",
      currency: "USD",
      description: "Pending Purchase",
      pending: true,
      date: Date.current
    )

    Lunchflow::TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_nil transaction.cleared_at
  end

  private

    def create_linked_lunchflow_account(remote_id: 901, name: "LF Test Checking")
      lf_account = Lunchflow::Account.create!(
        connection: lunchflow_connections(:one),
        remote_id: remote_id,
        name: name,
        currency: "USD",
        balance: "1000.00"
      )

      lf_bank_account = Account.create!(
        user: @user,
        currency: @currency,
        name: "Linked #{name}",
        kind: :asset,
        sourceable: lf_account
      )

      [ lf_account, lf_bank_account ]
    end
end
