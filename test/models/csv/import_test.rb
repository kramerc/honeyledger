require "test_helper"

class Csv::ImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = accounts(:asset_account)
  end

  test "is invalid when no file is attached" do
    csv_import = Csv::Import.new(user: @user, account: @account, state: "pending")
    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], "must be attached"
  end

  test "is invalid when the attached file exceeds MAX_FILE_BYTES" do
    csv_import = Csv::Import.new(user: @user, account: @account, state: "pending")
    csv_import.file.attach(
      io: StringIO.new("a"),
      filename: "tiny.csv",
      content_type: "text/csv"
    )
    csv_import.file.blob.update!(byte_size: Csv::Import::MAX_FILE_BYTES + 1)

    assert_not csv_import.valid?
    assert_match(/must be smaller than/, csv_import.errors[:file].first)
  end

  test "rejects an account belonging to another user" do
    other_account = accounts(:two)
    csv_import = Csv::Import.new(user: @user, account: other_account, state: "pending")
    csv_import.file.attach(io: StringIO.new("Date,Description,Amount\n"), filename: "f.csv", content_type: "text/csv")
    assert_not csv_import.valid?
    assert_includes csv_import.errors[:account], "must belong to you"
  end

  test "rejects a virtual account" do
    virtual = Account.create!(user: @user, name: "Opening Balance", kind: :revenue, virtual: true)
    csv_import = Csv::Import.new(user: @user, account: virtual, state: "pending")
    csv_import.file.attach(io: StringIO.new("Date,Description,Amount\n"), filename: "f.csv", content_type: "text/csv")
    assert_not csv_import.valid?
    assert_includes csv_import.errors[:account], "must be a real (non-virtual) account"
  end
end
