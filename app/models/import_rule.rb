class ImportRule < ApplicationRecord
  belongs_to :user
  belongs_to :account

  enum :match_type, %i[ contains exact starts_with ends_with ]

  validates :match_pattern, presence: true
  validates :match_pattern, uniqueness: { scope: [ :user_id, :match_type ] }
  validate :account_must_be_expense_or_revenue
  validate :account_must_belong_to_user

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

  private

  def account_must_be_expense_or_revenue
    return if account.nil?
    unless account.expense? || account.revenue?
      errors.add(:account, "must be an expense or revenue account")
    end
  end

  def account_must_belong_to_user
    return if account.nil? || user.nil?
    unless account.user_id == user_id
      errors.add(:account, "must belong to you")
    end
  end
end
