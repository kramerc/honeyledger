class ImportRule < ApplicationRecord
  belongs_to :user
  belongs_to :account, optional: true

  enum :match_type, %i[ contains exact starts_with ends_with ]

  normalizes :match_pattern, with: ->(value) { value.strip }

  validates :match_pattern, presence: true
  validates :match_pattern, uniqueness: { scope: [ :user_id, :match_type ], case_sensitive: false }
  validates :account_id, presence: true, unless: :exclude?
  validate :account_must_not_be_virtual, unless: :exclude?
  validate :account_must_belong_to_user, unless: :exclude?

  scope :for_description, ->(description) {
    downcased = description.to_s.strip.downcase
    escaped_pattern = "REPLACE(REPLACE(REPLACE(LOWER(match_pattern), '\\', '\\\\'), '%', '\\%'), '_', '\\_')"
    types = match_types
    where(
      "(match_type = :contains AND :desc LIKE '%' || #{escaped_pattern} || '%' ESCAPE '\\') " \
      "OR (match_type = :exact AND :desc = LOWER(match_pattern)) " \
      "OR (match_type = :starts_with AND :desc LIKE #{escaped_pattern} || '%' ESCAPE '\\') " \
      "OR (match_type = :ends_with AND :desc LIKE '%' || #{escaped_pattern} ESCAPE '\\')",
      desc: downcased, contains: types[:contains], exact: types[:exact],
      starts_with: types[:starts_with], ends_with: types[:ends_with]
    ).order(priority: :desc)
  }

  scope :for_kind, ->(kind) {
    joins(:account).where(accounts: { kind: kind })
  }

  # In-memory equivalent of for_description, for testing a single (possibly unsaved) rule
  # against a description without a query — used to preview a draft rule.
  def matches?(description)
    needle = match_pattern.to_s.strip.downcase
    return false if needle.blank?

    text = description.to_s.strip.downcase
    case match_type
    when "contains" then text.include?(needle)
    when "exact" then text == needle
    when "starts_with" then text.start_with?(needle)
    when "ends_with" then text.end_with?(needle)
    else false
    end
  end

  private

    def account_must_not_be_virtual
      return if account.nil?
      if account.virtual?
        errors.add(:account, "must not be a virtual account")
      end
    end

    def account_must_belong_to_user
      return if account.nil? || user.nil?
      unless account.user_id == user_id
        errors.add(:account, "must belong to you")
      end
    end
end
