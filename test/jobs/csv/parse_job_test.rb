require "test_helper"

class Csv::ParseJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @bank_account = accounts(:asset_account)
  end

  test "parses rows from the attached file and enqueues the import job" do
    csv_import = build_csv_import_with_file(<<~CSV)
      Date,Description,Amount
      2026-01-15,Coffee,-4.75
      2026-01-16,Refund,12.00
    CSV

    assert_enqueued_with(job: Csv::ImportTransactionsJob) do
      assert_difference "Csv::Transaction.count", 2 do
        Csv::ParseJob.perform_now(csv_import.id)
      end
    end

    csv_import.reload
    assert_equal "parsed", csv_import.state
    assert_not_nil csv_import.parsed_at
    assert_nil csv_import.error
  end

  test "is idempotent on re-parse via (import_id, row_index) uniqueness" do
    csv_import = build_csv_import_with_file(<<~CSV)
      Date,Description,Amount
      2026-01-15,Coffee,-4.75
    CSV

    Csv::ParseJob.perform_now(csv_import.id)
    assert_no_difference "Csv::Transaction.count" do
      Csv::ParseJob.perform_now(csv_import.id)
    end
  end

  test "persists remote_id from the mapped id column" do
    csv_import = build_csv_import_with_file(<<~CSV, mappings: signed_mappings.merge("id_column" => "Id"))
      Date,Description,Amount,Id
      2026-01-15,Coffee,-4.75,8521853000000001
    CSV

    Csv::ParseJob.perform_now(csv_import.id)
    assert_equal "8521853000000001", csv_import.transactions.sole.remote_id
  end

  test "re-parsing after adding an id column backfills remote_id and keeps existing sources" do
    csv_import = build_csv_import_with_file(<<~CSV)
      Date,Description,Amount,Id
      2026-01-15,Coffee,-4.75,8521853000000001
    CSV

    Csv::ParseJob.perform_now(csv_import.id)
    csv_transaction = csv_import.transactions.sole
    assert_nil csv_transaction.remote_id

    expense = Account.create!(user: @user, currency: @bank_account.currency, name: "Coffee", kind: :expense)
    ledger_transaction = Transaction.create!(
      user: @user, currency: @bank_account.currency, src_account: @bank_account, dest_account: expense,
      amount_minor: 475, description: "Coffee", transacted_at: Time.zone.local(2026, 1, 15)
    )
    TransactionSource.create!(ledger_transaction: ledger_transaction, sourceable: csv_transaction)

    csv_import.update!(column_mappings: signed_mappings.merge("id_column" => "Id"))
    assert_no_difference [ "Csv::Transaction.count", "TransactionSource.count" ] do
      Csv::ParseJob.perform_now(csv_import.id)
    end

    csv_transaction.reload
    assert_equal "8521853000000001", csv_transaction.remote_id
    assert_equal ledger_transaction, csv_transaction.ledger_transactions.sole
  end

  test "marks the import as failed when the CSV cannot be parsed" do
    content = <<~CSV
      Date,Description,Amount
      not a date,Coffee,-4.75
    CSV
    csv_import = build_csv_import_with_file(content)

    Csv::ParseJob.perform_now(csv_import.id)
    csv_import.reload
    assert_equal "failed", csv_import.state
    assert_match(/could not parse date/, csv_import.error)
  end

  test "no-ops when the import has no attached file" do
    csv_import = build_csv_import_with_file("")
    csv_import.file.purge
    csv_import.reload
    Csv::ParseJob.perform_now(csv_import.id)
    csv_import.reload
    assert_equal "mapped", csv_import.state
  end

  test "drops csv_transactions whose row_index is no longer produced after a re-parse with skip_rows" do
    csv_import = build_csv_import_with_file(<<~CSV)
      Date,Description,Amount
      2026-01-15,Coffee,-4.75
      2026-01-16,Refund,12.00
      2026-01-17,Other,-3.00
    CSV

    Csv::ParseJob.perform_now(csv_import.id)
    assert_equal [ 0, 1, 2 ], csv_import.transactions.order(:row_index).pluck(:row_index)

    csv_import.update!(column_mappings: csv_import.column_mappings.merge("skip_rows" => 2))
    Csv::ParseJob.perform_now(csv_import.id)
    assert_equal [ 2 ], csv_import.transactions.order(:row_index).pluck(:row_index)
  end

  test "still enqueues ImportTransactionsJob when no rows are produced" do
    csv_import = build_csv_import_with_file("Date,Description,Amount\n")

    assert_enqueued_with(job: Csv::ImportTransactionsJob, args: [ csv_import.id ]) do
      Csv::ParseJob.perform_now(csv_import.id)
    end
  end

  test "marks the import as failed and re-raises on an unexpected error" do
    csv_import = build_csv_import_with_file("Date,Description,Amount\n2026-01-15,Coffee,-1.00\n")

    Csv::Parser.stub_any_instance(:each_row, ->(*) { raise StandardError, "boom" }) do
      assert_raises(StandardError) do
        Csv::ParseJob.perform_now(csv_import.id)
      end
    end

    csv_import.reload
    assert_equal "failed", csv_import.state
    assert_match(/boom/, csv_import.error)
  end

  private

    def signed_mappings
      {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description" ]
      }
    end

    def build_csv_import_with_file(content, mappings: signed_mappings)
      csv_import = Csv::Import.new(
        user: @user,
        account: @bank_account,
        state: "mapped",
        column_mappings: mappings
      )
      csv_import.file.attach(
        io: StringIO.new(content),
        filename: "test.csv",
        content_type: "text/csv"
      )
      csv_import.save!
      csv_import
    end
end
