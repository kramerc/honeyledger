require "csv"

class Csv::Parser
  class Error < StandardError; end
  class RowError < Error
    attr_reader :row_index
    def initialize(message, row_index:)
      super("row #{row_index}: #{message}")
      @row_index = row_index
    end
  end

  AMOUNT_MODES = %w[ signed debit_credit sign_indicator ].freeze

  Row = Struct.new(:row_index, :transacted_at, :posted_at, :description, :amount_minor, :raw, keyword_init: true)

  def self.headers(io)
    new(io: io, mappings: {}, currency: nil).headers
  end

  def self.raw_preview(io, limit: 10)
    parser = new(io: io, mappings: {}, currency: nil)
    headers = parser.headers
    raw_rows = []
    ::CSV.parse(parser.send(:read_string), headers: true, liberal_parsing: true, skip_blanks: true).each do |csv_row|
      raw_rows << csv_row.to_h
      break if raw_rows.size >= limit
    end
    { headers: headers, rows: raw_rows }
  end

  def self.preview(io, mappings:, currency:, limit: 10)
    parser = new(io: io, mappings: mappings, currency: currency)
    parser.headers # ensure headers are loaded
    rows = []
    parser.each_row do |row|
      rows << row
      break if rows.size >= limit
    end
    { headers: parser.headers, rows: rows }
  end

  def initialize(io:, mappings:, currency:)
    @io = io
    @mappings = (mappings || {}).with_indifferent_access
    @currency = currency
  end

  def headers
    @headers ||= begin
      content = read_string
      first_line = content.each_line.first
      ::CSV.parse_line(first_line || "", liberal_parsing: true) || []
    end
  end

  # Yields a Row for each data row in the CSV. Caller is responsible for
  # rescuing RowError.
  def each_row
    return to_enum(:each_row) unless block_given?

    require_currency!
    require_mappings!

    skip_rows = (@mappings[:skip_rows] || 0).to_i
    options = { headers: true, liberal_parsing: true, skip_blanks: true }

    ::CSV.parse(read_string, **options).each_with_index do |csv_row, index|
      next if index < skip_rows

      raw_hash = csv_row.to_h
      amount_decimal = parse_amount(csv_row, index)
      amount_decimal = -amount_decimal if invert_amount?
      transacted_at = parse_date(
        compose_datetime(csv_row, @mappings[:date_column], @mappings[:time_column], @mappings[:timezone_column]),
        format: effective_date_format,
        field: "date",
        row_index: index
      )
      posted_at_value = posted_at_column.present? ? compose_datetime(csv_row, posted_at_column, @mappings[:time_column], @mappings[:timezone_column]) : nil
      posted_at = posted_at_value.present? ? parse_date(posted_at_value, format: effective_date_format, field: "posted_at", row_index: index) : nil
      description = build_description(csv_row)

      yield Row.new(
        row_index: index,
        transacted_at: transacted_at,
        posted_at: posted_at,
        description: description,
        amount_minor: minor_from(amount_decimal),
        raw: raw_hash
      )
    end
  end

  private

    def require_currency!
      raise Error, "currency is required to parse amounts" if @currency.nil?
    end

    def require_mappings!
      %i[ date_column amount_mode ].each do |key|
        raise Error, "#{key} is required" if @mappings[key].blank?
      end

      unless AMOUNT_MODES.include?(@mappings[:amount_mode].to_s)
        raise Error, "amount_mode must be one of #{AMOUNT_MODES.join(', ')}"
      end

      case @mappings[:amount_mode]
      when "signed"
        raise Error, "amount_column is required for signed mode" if @mappings[:amount_column].blank?
      when "debit_credit"
        raise Error, "debit_column and credit_column are required for debit_credit mode" if @mappings[:debit_column].blank? || @mappings[:credit_column].blank?
      when "sign_indicator"
        raise Error, "amount_column, sign_column, and debit_values are required for sign_indicator mode" if @mappings[:amount_column].blank? || @mappings[:sign_column].blank? || Array(@mappings[:debit_values]).empty?
      end
    end

    def read_string
      @read_string ||= begin
        @io.rewind if @io.respond_to?(:rewind)
        content = @io.read
        content = content.dup.force_encoding("UTF-8") if content.respond_to?(:force_encoding)
        content = content.sub(/\A﻿/, "")
        content
      end
    end

    def posted_at_column
      @mappings[:posted_at_column]
    end

    # Whether to flip the sign of the parsed amount before computing
    # amount_minor. Used for credit card / liability CSVs whose statement
    # convention reports purchases as positive and payments as negative,
    # opposite of the asset-style convention the import logic assumes.
    def invert_amount?
      ActiveModel::Type::Boolean.new.cast(@mappings[:invert_amount])
    end

    # Combines the value at `date_column` with the values at `time_column` and
    # `timezone_column` (if any) using single space separators, so a strftime
    # can match the value even when the file splits date, time, and timezone
    # across separate columns (PayPal exports do this).
    def compose_datetime(csv_row, date_column, time_column, timezone_column = nil)
      parts = [ csv_row[date_column].to_s.strip ]
      return parts.first if parts.first.empty?

      if time_column.present?
        time_value = csv_row[time_column].to_s.strip
        parts << time_value unless time_value.empty?
      end

      if timezone_column.present?
        tz_value = csv_row[timezone_column].to_s.strip
        parts << tz_value unless tz_value.empty?
      end

      parts.join(" ")
    end

    # If a timezone column is mapped but the user's format doesn't already
    # contain a %Z/%z token, auto-append " %Z" so strptime handles the
    # appended abbreviation. The user can still override by writing %z (numeric
    # offset) themselves.
    def effective_date_format
      format = @mappings[:date_format]
      return nil if format.blank?
      return format if @mappings[:timezone_column].blank?
      return format if format.include?("%Z") || format.include?("%z")
      "#{format} %Z"
    end

    def build_description(csv_row)
      columns = Array(@mappings[:description_columns]).reject(&:blank?)
      columns = [ @mappings[:description_column] ] if columns.empty? && @mappings[:description_column].present?
      values = columns.map { |column| csv_row[column].to_s.strip }.reject(&:empty?)
      values.join(" ").squeeze(" ").strip
    end

    def parse_amount(csv_row, row_index)
      case @mappings[:amount_mode]
      when "signed"
        parse_decimal(csv_row[@mappings[:amount_column]], field: @mappings[:amount_column], row_index: row_index)
      when "debit_credit"
        debit_raw = csv_row[@mappings[:debit_column]]
        credit_raw = csv_row[@mappings[:credit_column]]
        debit = parse_optional_decimal(debit_raw, field: @mappings[:debit_column], row_index: row_index)
        credit = parse_optional_decimal(credit_raw, field: @mappings[:credit_column], row_index: row_index)
        if debit && credit
          raise RowError.new("both debit and credit columns are populated", row_index: row_index)
        elsif debit
          -debit.abs
        elsif credit
          credit.abs
        else
          raise RowError.new("neither debit nor credit column is populated", row_index: row_index)
        end
      when "sign_indicator"
        amount = parse_decimal(csv_row[@mappings[:amount_column]], field: @mappings[:amount_column], row_index: row_index)
        sign_value = csv_row[@mappings[:sign_column]].to_s.strip
        debit_values = Array(@mappings[:debit_values]).map { |value| value.to_s.strip.downcase }
        if debit_values.include?(sign_value.downcase)
          -amount.abs
        else
          amount.abs
        end
      end
    end

    def parse_decimal(value, field:, row_index:)
      decimal = parse_optional_decimal(value, field: field, row_index: row_index)
      raise RowError.new("missing #{field}", row_index: row_index) if decimal.nil?
      decimal
    end

    def parse_optional_decimal(value, field:, row_index:)
      return nil if value.nil?
      cleaned = value.to_s.strip
      return nil if cleaned.empty?

      negative = false
      if cleaned.start_with?("(") && cleaned.end_with?(")")
        negative = true
        cleaned = cleaned[1..-2]
      end
      cleaned = cleaned.gsub(/[\$,\s]/, "")
      return nil if cleaned.empty?

      begin
        result = BigDecimal(cleaned)
      rescue ArgumentError, TypeError
        raise RowError.new("could not parse #{field.inspect} as a number: #{value.inspect}", row_index: row_index)
      end
      negative ? -result : result
    end

    def parse_date(value, format:, field:, row_index:)
      raise RowError.new("missing #{field}", row_index: row_index) if value.nil? || value.to_s.strip.empty?

      cleaned = value.to_s.strip

      if format.present?
        # Try the user-supplied format, then progressively shorter prefixes by
        # dropping trailing whitespace-separated segments. This covers two real
        # cases for files that split date/time/timezone across columns: a row
        # whose timezone cell is blank (try without trailing %Z), and a row
        # whose time and timezone cells are both blank (try date-only).
        segments = format.split(/\s+/).reject(&:empty?)
        formats_to_try = segments.size.downto(1).map { |n| segments.first(n).join(" ") }
        formats_to_try.each do |fmt|
          begin
            return ::DateTime.strptime(cleaned, fmt).to_time
          rescue ::Date::Error
            next
          end
        end
        raise RowError.new("could not parse #{field} #{value.inspect} with format #{format.inspect}", row_index: row_index)
      end

      begin
        ::DateTime.parse(cleaned).to_time
      rescue ::Date::Error, ArgumentError
        raise RowError.new(
          "could not parse #{field} #{value.inspect}; set a date format above " \
          "(e.g. %m/%d/%y for M/D/YY, %m/%d/%Y for M/D/YYYY, or %Y-%m-%d for ISO)",
          row_index: row_index
        )
      end
    end

    def minor_from(decimal)
      (decimal * (10 ** @currency.decimal_places)).round.to_i
    end
end
