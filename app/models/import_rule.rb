class ImportRule < ApplicationRecord
  belongs_to :user
  belongs_to :account

  enum :match_type, %i[ contains exact starts_with ends_with ]

  validates :match_pattern, presence: true
  validates :match_pattern, uniqueness: { scope: [ :user_id, :match_type ] }
  validate :account_must_be_expense_or_revenue

  scope :for_description, ->(description) {
    downcased = description.to_s.strip.downcase
    where(
      "(match_type = 0 AND :desc LIKE '%' || LOWER(match_pattern) || '%') " \
      "OR (match_type = 1 AND :desc = LOWER(match_pattern)) " \
      "OR (match_type = 2 AND :desc LIKE LOWER(match_pattern) || '%') " \
      "OR (match_type = 3 AND :desc LIKE '%' || LOWER(match_pattern))",
      desc: downcased
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
end
