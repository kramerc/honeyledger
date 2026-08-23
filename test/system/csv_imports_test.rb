require "application_system_test_case"

class CsvImportsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    @account = accounts(:asset_account)
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    sign_in_as(@user)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_adapter
  end

  test "upload, map columns, parse and import a CSV end-to-end" do
    fixture_path = Rails.root.join("tmp/test_import.csv")
    File.write(fixture_path, <<~CSV)
      Date,Description,Amount
      2026-01-15,Coffee Shop,-4.75
      2026-01-16,Refund Issued,12.00
    CSV

    visit account_transactions_path(@account)
    click_link "Import CSV"

    assert_text "CSV Imports"
    click_link "Upload a CSV"

    attach_file "csv_import_file", fixture_path.to_s
    click_button "Upload"

    assert_text "Map columns"

    select "Date", from: "csv_import_column_mappings_date_column"
    check "Description"
    select "Amount", from: "csv_import_column_mappings_amount_column"
    click_button "Save mapping"

    assert_text "Step 3: Confirm and import"
    assert_text "Coffee Shop"
    click_button "Parse and import these rows"
    assert_text "Parse and import enqueued"

    visit account_transactions_path(@account)
    assert_text "Coffee Shop"
    assert_text "Refund Issued"
  ensure
    File.delete(fixture_path) if defined?(fixture_path) && File.exist?(fixture_path)
  end

  test "dropping a CSV onto the upload form fills the file field" do
    visit new_account_csv_import_path(@account)

    drop_file_on_zone(name: "statement.csv", type: "text/csv", content: "Date,Description,Amount\n2026-01-15,Sample Vendor,-4.75\n")

    assert_no_selector ".file-drop__status", text: "not a .csv"
    assert_equal 1, page.evaluate_script("document.getElementById('csv_import_file').files.length")

    click_button "Upload"
    assert_text "Map columns"
  end

  test "dropping a non-CSV file onto the upload form is rejected" do
    visit new_account_csv_import_path(@account)

    drop_file_on_zone(name: "notes.txt", type: "text/plain", content: "hello")

    assert_selector ".file-drop__status", text: "notes.txt is not a .csv file."
    assert_equal 0, page.evaluate_script("document.getElementById('csv_import_file').files.length")
  end

  test "dropping an Excel workbook onto the upload form is rejected" do
    visit new_account_csv_import_path(@account)

    drop_file_on_zone(name: "workbook.xls", type: "application/vnd.ms-excel", content: "binary")

    assert_selector ".file-drop__status", text: "workbook.xls is not a .csv file."
    assert_equal 0, page.evaluate_script("document.getElementById('csv_import_file').files.length")
  end

  private

    # Capybara cannot drag a file in from the operating system, so synthesize the
    # drop event the browser would dispatch with the file already attached.
    def drop_file_on_zone(name:, type:, content:)
      page.execute_script(<<~JS, name, type, content)
        const [name, type, content] = arguments
        const transfer = new DataTransfer()
        transfer.items.add(new File([content], name, { type }))
        const event = new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer })
        document.querySelector(".file-drop").dispatchEvent(event)
      JS
    end

    def sign_in_as(user)
      visit new_user_session_path
      fill_in "Email", with: user.email
      fill_in "Password", with: "password123"
      click_button "Log in"
      assert_link "Logout"
    end
end
