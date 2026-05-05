require "test_helper"

class Csv::ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @other_user = users(:two)
    @account = accounts(:asset_account)
    sign_in @user
  end

  test "redirects unauthenticated requests" do
    sign_out @user
    get account_csv_imports_url(@account)
    assert_redirected_to new_user_session_url
  end

  test "GET account index shows the account's imports" do
    get account_csv_imports_url(@account)
    assert_response :success
  end

  test "GET top-level index lists imports across all the user's accounts" do
    get csv_imports_url
    assert_response :success
  end

  test "cannot view imports on another user's account" do
    other_account = accounts(:two)
    get account_csv_imports_url(other_account)
    assert_response :not_found
  end

  test "POST create attaches the file and redirects to show" do
    file = fixture_file_upload_csv("Date,Description,Amount\n2026-01-15,Coffee,-4.75\n")

    assert_difference "Csv::Import.count", 1 do
      post account_csv_imports_url(@account), params: { csv_import: { file: file } }
    end
    csv_import = Csv::Import.last
    assert_equal @user, csv_import.user
    assert_equal @account, csv_import.account
    assert csv_import.file.attached?
    assert_redirected_to account_csv_import_url(@account, csv_import)
  end

  test "POST create defaults column_mappings to the most recent prior import for the account" do
    prior_mappings = {
      "date_column" => "Date",
      "amount_mode" => "signed",
      "amount_column" => "Amount",
      "description_columns" => [ "Description" ]
    }
    Csv::Import.create!(user: @user, account: @account, state: "imported", column_mappings: prior_mappings)

    file = fixture_file_upload_csv("Date,Description,Amount\n2026-01-15,Coffee,-4.75\n")
    post account_csv_imports_url(@account), params: { csv_import: { file: file } }

    csv_import = Csv::Import.last
    assert_equal prior_mappings, csv_import.column_mappings
  end

  test "PATCH update saves the mapping and marks state as mapped" do
    csv_import = Csv::Import.create!(user: @user, account: @account, state: "pending")

    patch account_csv_import_url(@account, csv_import), params: {
      csv_import: {
        column_mappings: {
          date_column: "Date",
          amount_mode: "signed",
          amount_column: "Amount",
          description_columns: [ "Description" ],
          debit_values: "DEBIT, ACH_DEBIT"
        }
      }
    }
    assert_redirected_to confirm_account_csv_import_url(@account, csv_import)
    csv_import.reload
    assert_equal "mapped", csv_import.state
    assert_equal "Date", csv_import.column_mappings["date_column"]
    assert_equal [ "DEBIT", "ACH_DEBIT" ], csv_import.column_mappings["debit_values"]
  end

  test "GET confirm renders the parsed preview" do
    csv_import = Csv::Import.create!(
      user: @user,
      account: @account,
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description" ]
      }
    )
    csv_import.file.attach(fixture_file_upload_csv("Date,Description,Amount\n2026-01-15,Coffee,-4.75\n"))

    get confirm_account_csv_import_url(@account, csv_import)
    assert_response :success
    assert_match "Step 3: Confirm and import", response.body
    assert_match "Coffee", response.body
  end

  test "GET confirm redirects to mapping when state is pending" do
    csv_import = Csv::Import.create!(user: @user, account: @account, state: "pending")
    get confirm_account_csv_import_url(@account, csv_import)
    assert_redirected_to account_csv_import_url(@account, csv_import)
  end

  test "POST parse enqueues ParseJob once a mapping is saved" do
    csv_import = Csv::Import.create!(
      user: @user,
      account: @account,
      state: "mapped",
      column_mappings: { "date_column" => "Date", "amount_mode" => "signed", "amount_column" => "Amount" }
    )

    assert_enqueued_with(job: Csv::ParseJob, args: [ csv_import.id ]) do
      post parse_account_csv_import_url(@account, csv_import)
    end
    assert_redirected_to account_csv_import_url(@account, csv_import)
  end

  test "POST parse refuses to enqueue when the import is still pending" do
    csv_import = Csv::Import.create!(user: @user, account: @account, state: "pending")
    assert_no_enqueued_jobs only: Csv::ParseJob do
      post parse_account_csv_import_url(@account, csv_import)
    end
  end

  test "DELETE destroys the import" do
    csv_import = Csv::Import.create!(user: @user, account: @account, state: "pending")
    assert_difference "Csv::Import.count", -1 do
      delete account_csv_import_url(@account, csv_import)
    end
  end

  test "GET show pre-checks saved description_columns checkboxes" do
    csv_import = Csv::Import.create!(
      user: @user,
      account: @account,
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description", "Memo" ]
      }
    )
    csv_import.file.attach(fixture_file_upload_csv(<<~CSV))
      Date,Description,Memo,Amount
      2026-01-15,Coffee,Latte,-4.75
    CSV

    get account_csv_import_url(@account, csv_import)
    assert_response :success
    assert_match %r{<input[^>]*value="Description"[^>]*checked="checked"|<input[^>]*checked="checked"[^>]*value="Description"}, response.body
    assert_match %r{<input[^>]*value="Memo"[^>]*checked="checked"|<input[^>]*checked="checked"[^>]*value="Memo"}, response.body
    assert_no_match %r{<input[^>]*value="Date"[^>]*name="csv_import\[column_mappings\]\[description_columns\]\[\]"[^>]*checked="checked"}, response.body
  end

  private

    def fixture_file_upload_csv(content)
      Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: "test.csv")
    end
end
