require "test_helper"

class Csv::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_account = accounts(:asset_account)
  end

  test "imports an expense (negative amount_minor)" do
    csv_import = create_csv_import
    csv_transaction = csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current,
      raw: { "Date" => "2026-01-15", "Description" => "Coffee Shop", "Amount" => "-4.75" }
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do # auto-created expense counterpart
        Csv::ImportTransactionsJob.perform_now(csv_import.id)
      end
    end

    transaction = csv_transaction.ledger_transactions.first
    assert_equal @bank_account, transaction.src_account
    assert_equal "Coffee Shop", transaction.dest_account.name
    assert_equal "expense", transaction.dest_account.kind
    assert_equal 475, transaction.amount_minor
    assert_equal @currency, transaction.currency

    assert_equal "imported", csv_import.reload.state
    assert_not_nil csv_import.imported_at
  end

  test "imports a revenue (positive amount_minor)" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Salary Payment",
      amount_minor: 250000,
      synced_at: Time.current
    )

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end

    transaction = Transaction.last
    assert_equal @bank_account, transaction.dest_account
    assert_equal "Salary Payment", transaction.src_account.name
    assert_equal "revenue", transaction.src_account.kind
    assert_equal 250000, transaction.amount_minor
  end

  test "does not re-create a ledger transaction when re-running with no synced_at change" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
  end

  test "applies an import rule that routes to a non-balance-sheet account" do
    csv_import = create_csv_import
    rule_account = Account.create!(user: @user, currency: @currency, name: "Groceries", kind: :expense)
    @user.import_rules.create!(match_pattern: "MARKET", match_type: :contains, priority: 0, account: rule_account)

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "FARMERS MARKET",
      amount_minor: -1500,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    transaction = Transaction.last
    assert_equal rule_account, transaction.dest_account
    assert_equal @bank_account, transaction.src_account
  end

  test "excludes a transaction when an exclude rule matches" do
    csv_import = create_csv_import
    @user.import_rules.create!(match_pattern: "INTERNAL", match_type: :contains, priority: 0, exclude: true)

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "INTERNAL TRANSFER",
      amount_minor: -2000,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    transaction = Transaction.last
    assert transaction.excluded?
  end

  test "reconciles to an existing manual ledger transaction with matching description" do
    csv_import = create_csv_import
    counterpart = Account.create!(user: @user, currency: @currency, name: "Coffee Shop", kind: :expense)

    manual_transaction = Transaction.create!(
      user: @user,
      currency: @currency,
      src_account: @bank_account,
      dest_account: counterpart,
      description: "Coffee Shop",
      amount_minor: 475,
      transacted_at: 1.day.ago.beginning_of_day + 12.hours
    )

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago.beginning_of_day + 12.hours,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current
    )

    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end

    manual_transaction.reload
    assert_includes manual_transaction.transaction_sources.map(&:sourceable_type), "Csv::Transaction"
    assert_not_nil manual_transaction.synced_at
  end

  test "no-ops when the import has no rows" do
    csv_import = create_csv_import
    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
    assert_equal "imported", csv_import.reload.state
  end

  test "no-ops when the import does not exist" do
    assert_nothing_raised do
      Csv::ImportTransactionsJob.perform_now(0)
    end
  end

  private

    def create_csv_import
      csv_import = Csv::Import.new(user: @user, account: @bank_account, state: "parsed")
      csv_import.file.attach(
        io: StringIO.new("Date,Description,Amount\n"),
        filename: "stub.csv",
        content_type: "text/csv"
      )
      csv_import.save!
      csv_import
    end
end
