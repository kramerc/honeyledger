class Transaction < ApplicationRecord
  include Minorable
  unminorable :amount_minor, with: :currency
  unminorable :fx_amount_minor, with: :fx_currency

  belongs_to :user
  belongs_to :sourceable, polymorphic: true, optional: true

  belongs_to :category, optional: true

  belongs_to :src_account, class_name: "Account"
  belongs_to :dest_account, class_name: "Account"

  belongs_to :currency
  belongs_to :fx_currency, class_name: "Currency", optional: true

  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: "parent_transaction_id", dependent: :destroy

  before_validation :set_currency_from_dest_account
  before_validation :set_cleared_at_from_cleared

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?

  scope :opening_balances, -> { where(opening_balance: true) }

  validates :transacted_at, presence: true

  validate :src_account_accessible_to_user
  validate :dest_account_accessible_to_user

  validate :accounts_cannot_be_same, unless: -> { src_account_id.nil? || dest_account_id.nil? }
  validate :not_expense_to_revenue, if: -> { src_account&.expense? && dest_account&.revenue? }
  validate :not_revenue_to_expense, if: -> { src_account&.revenue? && dest_account&.expense? }

  def cleared
    return @cleared if defined?(@cleared)
    cleared_at.present?
  end

  def cleared=(value)
    @cleared = ActiveModel::Type::Boolean.new.cast(value)
  end

  def has_fx?
    fx_amount_minor.present? && fx_currency.present?
  end

  private

    def set_currency_from_dest_account
      self.currency_id = dest_account.currency_id if dest_account.present?
    end

    def set_cleared_at_from_cleared
      return unless defined?(@cleared)

      if @cleared
        self.cleared_at ||= Time.current
      else
        self.cleared_at = nil
      end
    end

    def mark_parent_as_split
      parent_transaction.update(split: true)
    end

    def unmark_parent_if_last_child
      parent_transaction.update(split: false) if parent_transaction.child_transactions.empty?
    end

    def src_account_accessible_to_user
      return if src_account.blank? || user.blank?

      unless src_account.accessible_by?(user)
        errors.add(:src_account, "must be accessible to you")
      end
    end

    def dest_account_accessible_to_user
      return if dest_account.blank? || user.blank?

      unless dest_account.accessible_by?(user)
        errors.add(:dest_account, "must be accessible to you")
      end
    end

    def accounts_cannot_be_same
      if src_account_id == dest_account_id
        errors.add(:src_account, "cannot be the same as dest account")
      end
    end

    def not_revenue_to_expense
      if src_account.revenue? && dest_account.expense?
        errors.add(:src_account, "cannot be a revenue account to an expense dest account")
      end
    end

    def not_expense_to_revenue
      if src_account.expense? && dest_account.revenue?
        errors.add(:src_account, "cannot be an expense account to a revenue dest account")
      end
    end
end
