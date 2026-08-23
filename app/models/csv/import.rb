class Csv::Import < ApplicationRecord
  STATES = %w[ pending mapped parsed imported failed ].freeze
  MAX_FILE_BYTES = 25.megabytes
  ALLOWED_EXTENSIONS = %w[ csv ].freeze
  # How much of the upload to sample when checking that it is readable text.
  TEXT_SAMPLE_BYTES = 8.kilobytes

  belongs_to :user
  belongs_to :account
  has_many :transactions, class_name: "Csv::Transaction", foreign_key: :import_id, dependent: :destroy
  has_one_attached :file

  validates :state, inclusion: { in: STATES }
  validates :file, presence: true
  validate :account_belongs_to_user
  validate :account_is_real
  validate :file_within_size_limit, if: -> { file.attached? }
  validate :file_has_csv_extension, if: -> { file.attached? }
  validate :file_is_readable_text, if: -> { file_changing? && errors[:file].empty? }

  STATES.each do |state_name|
    define_method("#{state_name}?") { state == state_name }
  end

  # Returns the column_mappings hash from the most recent prior import for the same
  # ledger account, or an empty hash. Used to pre-fill the mapping form on a new
  # import so the user does not have to re-map columns for the same institution's
  # export format.
  def self.last_mapping_for(account:)
    where(account_id: account.id)
      .where.not(column_mappings: {})
      .order(created_at: :desc)
      .limit(1)
      .pick(:column_mappings) || {}
  end

  def filename
    file.attached? ? file.filename.to_s : nil
  end

  # Whether the saved column_mappings have every field the parser needs to
  # process a row. Used to gate the confirm/parse step in the controller and
  # the "Parse and import" button in the confirm view, so the user can't
  # enqueue a parse that will fail at parse-time validation.
  def mappings_complete?
    return false if column_mappings.blank?
    mapping = column_mappings.with_indifferent_access
    return false if mapping[:date_column].blank? || mapping[:amount_mode].blank?
    case mapping[:amount_mode]
    when "signed", "sign_indicator"
      mapping[:amount_column].present?
    when "debit_credit"
      mapping[:debit_column].present? && mapping[:credit_column].present?
    else
      false
    end
  end

  private

    def account_belongs_to_user
      return if account.blank? || user.blank?
      errors.add(:account, "must belong to you") unless account.accessible_by?(user)
    end

    def account_is_real
      return if account.blank?
      errors.add(:account, "must be a real (non-virtual) account") if account.virtual?
    end

    def file_within_size_limit
      if file.byte_size > MAX_FILE_BYTES
        errors.add(:file, "must be smaller than #{ActiveSupport::NumberHelper.number_to_human_size(MAX_FILE_BYTES)}")
      end
    end

    # The browser's content type is unreliable (Windows reports .csv files as
    # application/vnd.ms-excel), so the extension is what we check.
    def file_has_csv_extension
      extension = file.filename.extension_without_delimiter.to_s.downcase
      return if ALLOWED_EXTENSIONS.include?(extension)

      errors.add(:file, "must be a CSV file (.#{ALLOWED_EXTENSIONS.join(', .')})")
    end

    # Rejects uploads whose bytes the parser cannot read (a spreadsheet
    # renamed to .csv, an invalid byte sequence). Samples the start of the
    # file rather than downloading all of it. A multi-byte character split by
    # the sample boundary is not a failure, so the sample is trimmed back to a
    # character boundary before the check.
    def file_is_readable_text
      sample = read_file_sample
      return if sample.nil? || Csv::Parser.readable_text?(trim_to_character_boundary(sample))

      errors.add(:file, Csv::Parser::UNREADABLE_MESSAGE)
    end

    def file_changing?
      attachment_changes["file"].present?
    end

    # Before the record is saved the blob has not been uploaded to the storage
    # service yet, so the bytes are read from the pending attachable: either
    # an uploaded file object or an `io:` hash as passed to `file.attach`.
    def read_file_sample
      pending = attachment_changes["file"].attachable
      io = pending.is_a?(Hash) ? pending[:io] : pending
      return nil unless io.respond_to?(:read)

      io.rewind if io.respond_to?(:rewind)
      sample = io.read(TEXT_SAMPLE_BYTES)
      io.rewind if io.respond_to?(:rewind)
      sample
    end

    def trim_to_character_boundary(sample)
      utf8 = sample.to_s.dup.force_encoding("UTF-8")
      return utf8 if utf8.valid_encoding? || sample.bytesize < TEXT_SAMPLE_BYTES

      # Drop up to three trailing bytes (the longest partial UTF-8 sequence) so
      # a character cut by the sample boundary is not reported as invalid.
      3.times do
        utf8 = utf8.byteslice(0, utf8.bytesize - 1)
        break if utf8.valid_encoding?
      end
      utf8
    end
end
