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

  test "POST create rejects an upload with no file" do
    assert_no_difference "Csv::Import.count" do
      post account_csv_imports_url(@account), params: { csv_import: { file: nil } }
    end
    assert_response :unprocessable_entity
  end

  test "POST create defaults column_mappings to the most recent prior import for the account" do
    prior_mappings = {
      "date_column" => "Date",
      "amount_mode" => "signed",
      "amount_column" => "Amount",
      "description_columns" => [ "Description" ]
    }
    build_csv_import(state: "imported", column_mappings: prior_mappings).save!

    file = fixture_file_upload_csv("Date,Description,Amount\n2026-01-15,Coffee,-4.75\n")
    post account_csv_imports_url(@account), params: { csv_import: { file: file } }

    csv_import = Csv::Import.last
    assert_equal prior_mappings, csv_import.column_mappings
  end

  test "PATCH update saves the mapping and marks state as mapped" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

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

  test "PATCH update casts invert_amount to a boolean" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    patch account_csv_import_url(@account, csv_import), params: {
      csv_import: { column_mappings: { date_column: "Date", amount_mode: "signed", amount_column: "Amount", invert_amount: "1" } }
    }
    csv_import.reload
    assert_equal true, csv_import.column_mappings["invert_amount"]

    patch account_csv_import_url(@account, csv_import), params: {
      csv_import: { column_mappings: { date_column: "Date", amount_mode: "signed", amount_column: "Amount", invert_amount: "0" } }
    }
    csv_import.reload
    assert_equal false, csv_import.column_mappings["invert_amount"]
  end

  test "PATCH update tolerates a request body with no column_mappings" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    patch account_csv_import_url(@account, csv_import), params: { csv_import: {} }
    csv_import.reload
    assert_equal "mapped", csv_import.state
    # Default no-op mapping; the existing reject(&:blank?) normalizes the
    # description_columns array to empty rather than dropping the key.
    assert_equal({ "description_columns" => [] }, csv_import.column_mappings)
  end

  test "GET confirm renders the parsed preview" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description" ]
      }
    )
    csv_import.save!

    get confirm_account_csv_import_url(@account, csv_import)
    assert_response :success
    assert_match "Step 3: Confirm and import", response.body
    assert_match "Coffee", response.body
  end

  test "GET confirm redirects to mapping when state is pending" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    get confirm_account_csv_import_url(@account, csv_import)
    assert_redirected_to account_csv_import_url(@account, csv_import)
  end

  test "POST parse enqueues ParseJob once a mapping is saved" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: { "date_column" => "Date", "amount_mode" => "signed", "amount_column" => "Amount" }
    )
    csv_import.save!

    assert_enqueued_with(job: Csv::ParseJob, args: [ csv_import.id ]) do
      post parse_account_csv_import_url(@account, csv_import)
    end
    assert_redirected_to account_csv_import_url(@account, csv_import)
  end

  test "POST parse refuses to enqueue when the import is still pending" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    assert_no_enqueued_jobs only: Csv::ParseJob do
      post parse_account_csv_import_url(@account, csv_import)
    end
  end

  test "DELETE destroys the import" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    assert_difference "Csv::Import.count", -1 do
      delete account_csv_import_url(@account, csv_import)
    end
  end

  test "GET new renders the upload form" do
    get new_account_csv_import_url(@account)
    assert_response :success
  end

  test "PATCH update re-renders show with errors when validation fails" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!
    csv_import.file.purge

    patch account_csv_import_url(@account, csv_import), params: {
      csv_import: { column_mappings: { date_column: "Date", amount_mode: "signed", amount_column: "Amount" } }
    }
    assert_response :unprocessable_entity
  end

  test "GET show with debit_credit mappings renders the mapped preview" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "debit_credit",
        "debit_column" => "Debit",
        "credit_column" => "Credit",
        "description_columns" => [ "Description" ]
      },
      content: "Date,Description,Debit,Credit\n2026-01-15,Coffee,4.75,\n"
    )
    csv_import.save!

    get account_csv_import_url(@account, csv_import)
    assert_response :success
  end

  test "GET show with an unknown amount_mode renders without a parsed preview" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: { "date_column" => "Date", "amount_mode" => "garbage" }
    )
    csv_import.save!

    get account_csv_import_url(@account, csv_import)
    assert_response :success
    assert_no_match "Mapped preview", response.body
  end

  test "GET show falls back to an empty raw preview when raw parsing raises a malformed CSV error" do
    csv_import = build_csv_import(state: "pending")
    csv_import.save!

    Csv::Parser.stub(:raw_preview, ->(*) { raise ::CSV::MalformedCSVError.new("Unquoted fields", 1) }) do
      get account_csv_import_url(@account, csv_import)
    end
    assert_response :success
  end

  test "GET show surfaces parser RowError as a preview error message" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description" ]
      },
      content: "Date,Description,Amount\nnot a date,Coffee,-1.00\n"
    )
    csv_import.save!

    get account_csv_import_url(@account, csv_import)
    assert_response :success
    assert_match "Preview error", response.body
  end

  test "GET show pre-checks saved description_columns checkboxes" do
    csv_import = build_csv_import(
      state: "mapped",
      column_mappings: {
        "date_column" => "Date",
        "amount_mode" => "signed",
        "amount_column" => "Amount",
        "description_columns" => [ "Description", "Memo" ]
      },
      content: "Date,Description,Memo,Amount\n2026-01-15,Coffee,Latte,-4.75\n"
    )
    csv_import.save!

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

    def build_csv_import(state:, column_mappings: {}, content: "Date,Description,Amount\n2026-01-15,Coffee,-4.75\n")
      csv_import = Csv::Import.new(
        user: @user,
        account: @account,
        state: state,
        column_mappings: column_mappings
      )
      csv_import.file.attach(
        io: StringIO.new(content),
        filename: "test.csv",
        content_type: "text/csv"
      )
      csv_import
    end
end
