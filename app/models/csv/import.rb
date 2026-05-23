class Csv::Import < ApplicationRecord
  STATES = %w[ pending mapped parsed imported failed ].freeze
  MAX_FILE_BYTES = 25.megabytes

  belongs_to :user
  belongs_to :account
  has_many :transactions, class_name: "Csv::Transaction", foreign_key: :import_id, dependent: :destroy
  has_one_attached :file

  validates :state, inclusion: { in: STATES }
  validates :file, presence: true
  validate :account_belongs_to_user
  validate :account_is_real
  validate :file_within_size_limit, if: -> { file.attached? }

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
end
