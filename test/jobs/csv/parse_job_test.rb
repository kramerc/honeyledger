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
    csv_import = Csv::Import.create!(
      user: @user,
      account: @bank_account,
      state: "mapped",
      column_mappings: signed_mappings
    )
    Csv::ParseJob.perform_now(csv_import.id)
    csv_import.reload
    assert_equal "mapped", csv_import.state
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
      csv_import = Csv::Import.create!(
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
      csv_import
    end
end
