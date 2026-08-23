require "test_helper"

class Csv::ImportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = accounts(:asset_account)
  end

  test "is invalid when no file is attached" do
    csv_import = Csv::Import.new(user: @user, account: @account, state: "pending")
    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], "can't be blank"
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

  test "is invalid when the attached file does not have a .csv extension" do
    csv_import = build_import_with_file("Date,Description,Amount\n", filename: "statement.xls", content_type: "application/vnd.ms-excel")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], "must be a CSV file (.csv)"
  end

  test "accepts a .CSV extension regardless of case and browser content type" do
    csv_import = build_import_with_file("Date,Description,Amount\n", filename: "STATEMENT.CSV", content_type: "application/vnd.ms-excel")

    assert csv_import.valid?, csv_import.errors.full_messages.join(", ")
  end

  test "is invalid when the attached file is not valid UTF-8 text" do
    csv_import = build_import_with_file("\xFF\xFE\x00binary\x80".b, filename: "renamed.csv")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], Csv::Parser::UNREADABLE_MESSAGE
  end

  test "is invalid when the attached file contains NUL bytes" do
    csv_import = build_import_with_file("Date,Description\0,Amount\n", filename: "renamed.csv")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], Csv::Parser::UNREADABLE_MESSAGE
  end

  test "accepts a UTF-8 file with a BOM and multi-byte characters" do
    csv_import = build_import_with_file("\uFEFFDate,Description,Amount\n2026-01-15,Café,-4.75\n", filename: "statement.csv")

    assert csv_import.valid?, csv_import.errors.full_messages.join(", ")
  end

  test "accepts a file whose text sample boundary splits a multi-byte character" do
    # Fill the sample window so its final byte lands in the middle of "é".
    padding = "a" * (Csv::Import::TEXT_SAMPLE_BYTES - 1)
    csv_import = build_import_with_file("#{padding}é,more\n", filename: "statement.csv")

    assert csv_import.valid?, csv_import.errors.full_messages.join(", ")
  end

  test "accepts a sample boundary that splits a three- or four-byte character" do
    { "three-byte" => "\u20AC", "four-byte" => "\u{1F600}" }.each do |label, character|
      padding = "a" * (Csv::Import::TEXT_SAMPLE_BYTES - 2)
      csv_import = build_import_with_file("#{padding}#{character},more\n", filename: "statement.csv")

      assert csv_import.valid?, "#{label}: #{csv_import.errors.full_messages.join(', ')}"
    end
  end

  test "rejects stray continuation bytes at the end of the sample" do
    padding = "a" * (Csv::Import::TEXT_SAMPLE_BYTES - 3)
    csv_import = build_import_with_file("#{padding}\x80\x80\x80more\n".b, filename: "statement.csv")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], Csv::Parser::UNREADABLE_MESSAGE
  end

  test "rejects an invalid byte near the end of the sample even when the file continues" do
    padding = "a" * (Csv::Import::TEXT_SAMPLE_BYTES - 2)
    csv_import = build_import_with_file("#{padding}\xFFa,more\n".b, filename: "statement.csv")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], Csv::Parser::UNREADABLE_MESSAGE
  end

  test "rejects a file that ends exactly at the sample boundary with a truncated character" do
    padding = "a" * (Csv::Import::TEXT_SAMPLE_BYTES - 1)
    csv_import = build_import_with_file("#{padding}\xC3".b, filename: "statement.csv")

    assert_not csv_import.valid?
    assert_includes csv_import.errors[:file], Csv::Parser::UNREADABLE_MESSAGE
  end

  test "does not re-sample the file when saving a persisted import without changing the attachment" do
    csv_import = build_import_with_file("Date,Description,Amount\n", filename: "statement.csv")
    csv_import.save!

    Csv::Parser.stub(:readable_text?, ->(*) { raise "sampled the file again" }) do
      assert csv_import.update(state: "mapped")
    end
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

  private

    def build_import_with_file(content, filename:, content_type: "text/csv")
      csv_import = Csv::Import.new(user: @user, account: @account, state: "pending")
      csv_import.file.attach(io: StringIO.new(content), filename: filename, content_type: content_type)
      csv_import
    end
end
