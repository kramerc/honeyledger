require "test_helper"

class Csv::ParserTest < ActiveSupport::TestCase
  setup do
    @usd = currencies(:usd)
    @jpy = currencies(:jpy)
  end

  test "signed mode parses negative as expense and positive as revenue" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Coffee,-4.75
      2026-01-16,Refund,12.00
    CSV

    rows = parse(content, mappings: signed_mappings, currency: @usd)
    assert_equal 2, rows.size
    assert_equal(-475, rows[0].amount_minor)
    assert_equal "Coffee", rows[0].description
    assert_equal Time.zone.local(2026, 1, 15), rows[0].transacted_at
    assert_equal 1200, rows[1].amount_minor
  end

  test "signed mode strips dollar sign and commas" do
    content = "Date,Description,Amount\n2026-01-15,Big buy,\"$1,234.56\"\n"
    rows = parse(content, mappings: signed_mappings, currency: @usd)
    assert_equal 123456, rows.first.amount_minor
  end

  test "signed mode treats parenthesized amounts as negative" do
    content = "Date,Description,Amount\n2026-01-15,Charge,(75.00)\n"
    rows = parse(content, mappings: signed_mappings, currency: @usd)
    assert_equal(-7500, rows.first.amount_minor)
  end

  test "debit_credit mode picks debit as negative and credit as positive" do
    content = <<~CSV
      Date,Description,Debit,Credit
      2026-01-15,Coffee,4.75,
      2026-01-16,Deposit,,100.00
    CSV
    mappings = base_mappings.merge(amount_mode: "debit_credit", debit_column: "Debit", credit_column: "Credit")
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal(-475, rows[0].amount_minor)
    assert_equal 10000, rows[1].amount_minor
  end

  test "debit_credit mode raises when both debit and credit are populated" do
    content = "Date,Description,Debit,Credit\n2026-01-15,Bad,1.00,2.00\n"
    mappings = base_mappings.merge(amount_mode: "debit_credit", debit_column: "Debit", credit_column: "Credit")
    error = assert_raises(Csv::Parser::RowError) { parse(content, mappings: mappings, currency: @usd) }
    assert_match(/both debit and credit/, error.message)
  end

  test "debit_credit mode raises when neither debit nor credit is populated" do
    content = "Date,Description,Debit,Credit\n2026-01-15,Empty,,\n"
    mappings = base_mappings.merge(amount_mode: "debit_credit", debit_column: "Debit", credit_column: "Credit")
    assert_raises(Csv::Parser::RowError) { parse(content, mappings: mappings, currency: @usd) }
  end

  test "sign_indicator mode flips sign based on debit_values" do
    content = <<~CSV
      Date,Description,Type,Amount
      2026-01-15,Coffee,DEBIT,4.75
      2026-01-16,Deposit,CREDIT,100.00
      2026-01-17,Withdrawal,ach_debit,20.00
    CSV
    mappings = base_mappings.merge(
      amount_mode: "sign_indicator",
      amount_column: "Amount",
      sign_column: "Type",
      debit_values: [ "DEBIT", "ACH_DEBIT" ]
    )
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal(-475, rows[0].amount_minor)
    assert_equal 10000, rows[1].amount_minor
    assert_equal(-2000, rows[2].amount_minor) # case-insensitive match
  end

  test "uses date_format strftime when provided" do
    content = "Date,Description,Amount\n02/15/2026,Coffee,-4.75\n"
    mappings = signed_mappings.merge(date_format: "%m/%d/%Y")
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal Time.zone.local(2026, 2, 15), rows.first.transacted_at
  end

  test "uses flexible date parsing when no date_format is provided" do
    content = "Date,Description,Amount\n2026-02-15,Coffee,-4.75\n"
    rows = parse(content, mappings: signed_mappings, currency: @usd)
    assert_equal Time.zone.local(2026, 2, 15), rows.first.transacted_at
  end

  test "raises RowError on unparseable dates" do
    content = "Date,Description,Amount\nnot a date,Coffee,-4.75\n"
    error = assert_raises(Csv::Parser::RowError) { parse(content, mappings: signed_mappings, currency: @usd) }
    assert_equal 0, error.row_index
  end

  test "falls back to date-only format when user-supplied format includes time tokens but column lacks them" do
    content = "Date,Description,Amount\n04/13/2026,Coffee,-4.75\n"
    mappings = signed_mappings.merge(date_format: "%m/%d/%Y %H:%M:%S")
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal Time.zone.local(2026, 4, 13), rows.first.transacted_at
  end

  test "combines date_column and time_column when time_column is mapped" do
    content = "Date,Time,Description,Amount\n04/13/2026,14:30:00,Coffee,-4.75\n"
    mappings = signed_mappings.merge(date_format: "%m/%d/%Y %H:%M:%S", time_column: "Time")
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal Time.zone.local(2026, 4, 13, 14, 30, 0), rows.first.transacted_at
  end

  test "tolerates blank time values when time_column is mapped" do
    content = "Date,Time,Description,Amount\n04/13/2026,,Coffee,-4.75\n"
    mappings = signed_mappings.merge(date_format: "%m/%d/%Y %H:%M:%S", time_column: "Time")
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal Time.zone.local(2026, 4, 13), rows.first.transacted_at
  end

  test "applies the timezone abbreviation from timezone_column when mapped" do
    content = "Date,Time,TimeZone,Description,Amount\n04/13/2026,11:00:00,PDT,Coffee,-4.75\n"
    mappings = signed_mappings.merge(
      date_format: "%m/%d/%Y %H:%M:%S",
      time_column: "Time",
      timezone_column: "TimeZone"
    )
    rows = parse(content, mappings: mappings, currency: @usd)
    # 11:00 PDT == 18:00 UTC (PDT is UTC-7)
    assert_equal Time.utc(2026, 4, 13, 18, 0, 0), rows.first.transacted_at.utc
  end

  test "tolerates a blank timezone cell mid-import by dropping the %Z token" do
    content = <<~CSV
      Date,Time,TimeZone,Description,Amount
      04/13/2026,11:00:00,PDT,Coffee,-4.75
      04/14/2026,12:00:00,,Refund,5.00
    CSV
    mappings = signed_mappings.merge(
      date_format: "%m/%d/%Y %H:%M:%S",
      time_column: "Time",
      timezone_column: "TimeZone"
    )
    rows = parse(content, mappings: mappings, currency: @usd)
    # First row has TZ → 11:00 PDT == 18:00 UTC.
    assert_equal Time.utc(2026, 4, 13, 18, 0, 0), rows[0].transacted_at.utc
    # Second row has no TZ; we want to keep the time and parse without %Z.
    # Stored time-of-day is 12:00:00 in whatever zone DateTime defaults to.
    assert_equal 12, rows[1].transacted_at.hour
  end

  test "respects a user-supplied %Z token without auto-appending one" do
    content = "Date,TimeZone,Description,Amount\n04/13/2026,PST,Coffee,-4.75\n"
    mappings = signed_mappings.merge(
      date_format: "%m/%d/%Y %Z",
      timezone_column: "TimeZone"
    )
    rows = parse(content, mappings: mappings, currency: @usd)
    # Midnight PST == 08:00 UTC (PST is UTC-8)
    assert_equal Time.utc(2026, 4, 13, 8, 0, 0), rows.first.transacted_at.utc
  end

  test "raises informative RowError when neither full nor truncated user format matches" do
    content = "Date,Description,Amount\n2026-04-13,Coffee,-4.75\n"
    mappings = signed_mappings.merge(date_format: "%m/%d/%Y")
    error = assert_raises(Csv::Parser::RowError) { parse(content, mappings: mappings, currency: @usd) }
    assert_match(/with format/, error.message)
  end

  test "concatenates multiple description columns with spaces" do
    content = "Date,Merchant,Memo,Amount\n2026-01-15,ACME,Coffee shop,-4.75\n"
    mappings = signed_mappings.merge(description_columns: [ "Merchant", "Memo" ])
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal "ACME Coffee shop", rows.first.description
  end

  test "respects skip_rows" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,Skip me,1.00
      2026-01-16,Keep me,2.00
    CSV
    mappings = signed_mappings.merge(skip_rows: 1)
    rows = parse(content, mappings: mappings, currency: @usd)
    assert_equal 1, rows.size
    assert_equal "Keep me", rows.first.description
  end

  test "uses currency decimal_places when computing amount_minor" do
    content = "Date,Description,Amount\n2026-01-15,Yen,-1500\n"
    rows = parse(content, mappings: signed_mappings, currency: @jpy)
    assert_equal(-1500, rows.first.amount_minor)
  end

  test "handles UTF-8 BOM at the start of the file" do
    content = "﻿Date,Description,Amount\n2026-01-15,Coffee,-4.75\n"
    rows = parse(content, mappings: signed_mappings, currency: @usd)
    assert_equal 1, rows.size
    assert_equal(-475, rows.first.amount_minor)
  end

  test "headers returns the header row" do
    content = "Date,Description,Amount\n2026-01-15,Coffee,-4.75\n"
    headers = Csv::Parser.headers(StringIO.new(content))
    assert_equal [ "Date", "Description", "Amount" ], headers
  end

  test "preview returns headers and up to limit rows" do
    content = "Date,Description,Amount\n2026-01-15,A,-1\n2026-01-16,B,-2\n2026-01-17,C,-3\n"
    result = Csv::Parser.preview(StringIO.new(content), mappings: signed_mappings, currency: @usd, limit: 2)
    assert_equal [ "Date", "Description", "Amount" ], result[:headers]
    assert_equal 2, result[:rows].size
  end

  test "raises when amount_mode is missing" do
    parser = Csv::Parser.new(io: StringIO.new("Date,Description,Amount\n"), mappings: { date_column: "Date" }, currency: @usd)
    assert_raises(Csv::Parser::Error) { parser.each_row.to_a }
  end

  test "raises when amount_mode is unknown" do
    parser = Csv::Parser.new(
      io: StringIO.new("Date,Description,Amount\n"),
      mappings: { date_column: "Date", amount_mode: "bogus", amount_column: "Amount" },
      currency: @usd
    )
    error = assert_raises(Csv::Parser::Error) { parser.each_row.to_a }
    assert_match(/amount_mode must be one of/, error.message)
  end

  test "raises a RowError when an amount column value is not a number" do
    content = "Date,Description,Amount\n2026-01-15,Coffee,abc\n"
    error = assert_raises(Csv::Parser::RowError) { parse(content, mappings: signed_mappings, currency: @usd) }
    assert_match(/could not parse/, error.message)
  end

  test "invert_amount flips the parsed sign" do
    content = <<~CSV
      Date,Description,Amount
      2026-01-15,PURCHASE,4.75
      2026-01-16,PAYMENT,-100.00
    CSV
    rows = parse(content, mappings: signed_mappings.merge(invert_amount: true), currency: @usd)
    # +4.75 -> expense (-475), -100.00 -> revenue/payment (+10000)
    assert_equal(-475, rows[0].amount_minor)
    assert_equal 10000, rows[1].amount_minor
  end

  test "invert_amount accepts truthy strings" do
    content = "Date,Description,Amount\n2026-01-15,PURCHASE,4.75\n"
    [ "1", "true", "on", true ].each do |truthy|
      rows = parse(content, mappings: signed_mappings.merge(invert_amount: truthy), currency: @usd)
      assert_equal(-475, rows.first.amount_minor, "expected #{truthy.inspect} to count as truthy")
    end
  end

  test "invert_amount=false leaves the sign alone" do
    content = "Date,Description,Amount\n2026-01-15,PURCHASE,4.75\n"
    rows = parse(content, mappings: signed_mappings.merge(invert_amount: false), currency: @usd)
    assert_equal 475, rows.first.amount_minor
  end

  private

    def parse(content, mappings:, currency:)
      Csv::Parser.new(io: StringIO.new(content), mappings: mappings, currency: currency).each_row.to_a
    end

    def base_mappings
      {
        date_column: "Date",
        description_columns: [ "Description" ],
        skip_rows: 0
      }
    end

    def signed_mappings
      base_mappings.merge(amount_mode: "signed", amount_column: "Amount")
    end
end
