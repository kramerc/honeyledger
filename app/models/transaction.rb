class Transaction < ApplicationRecord
  include Minorable
  unminorable :amount_minor, with: :currency
  unminorable :fx_amount_minor, with: :fx_currency

  belongs_to :user
  belongs_to :sourceable, polymorphic: true, optional: true

  belongs_to :category, optional: true

  # These are still required, but presence is validated differently to handle opening balances, which set the accounts
  # before save based on #opening_balance_target_account
  belongs_to :src_account, optional: true, class_name: "Account"
  belongs_to :dest_account, optional: true, class_name: "Account"
  validates_presence_of :src_account, :dest_account, message: :required, unless: :opening_balance?

  # Currency (but not FX) is required, but presence is validated differently to handle opening balances, which set the
  # accounts before save based on #opening_balance_target_account
  belongs_to :currency, optional: true
  belongs_to :fx_currency, class_name: "Currency", optional: true
  validates_presence_of :currency, unless: :opening_balance?

  belongs_to :parent_transaction, class_name: "Transaction", optional: true
  has_many :child_transactions, class_name: "Transaction", foreign_key: "parent_transaction_id", dependent: :destroy

  before_validation :assign_currency_from_dest_account, unless: :opening_balance?
  before_validation :assign_cleared_at_from_cleared, unless: :opening_balance?

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?

  scope :opening_balances, -> { where(opening_balance: true) }
  validate :opening_balance_is_valid, if: :opening_balance?
  before_save :assign_attributes_for_opening_balance, if: :opening_balance?

  validates :amount_minor, numericality: { allow_blank: true, unless: :amount_written? } # Blank is translated to 0
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

  def opening_balance_target_account
    return nil unless opening_balance?
    return @opening_balance_target_account if defined?(@opening_balance_target_account)

    if src_account&.real?
      @opening_balance_target_account = src_account
    elsif dest_account&.real?
      @opening_balance_target_account = dest_account
    else
      @opening_balance_target_account = nil
    end
  end

  def opening_balance_target_account=(account)
    @opening_balance_target_account = account
  end

  private

    def assign_currency_from_dest_account
      self.currency = dest_account.currency if dest_account.present? && !dest_account.virtual?
    end

    def assign_cleared_at_from_cleared
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

    def opening_balance_is_valid
      if opening_balance_target_account.blank?
        errors.add(:opening_balance_target_account, :required, message: "is required for opening balance")
      end

      if amount_written?
        if amount.blank?
          errors.add(:amount, :blank, message: "can't be blank for opening balance")
        elsif amount.to_d.zero?
          begin
            BigDecimal(amount) # Add the error only if it was a number, as to_d coerces to 0
            errors.add(:amount, :zero, message: "can't be zero for opening balance")
          rescue ArgumentError, TypeError
            # amount is not a number, which Minorable validated
          end
        end
      elsif amount_minor.blank?
        errors.add(:amount_minor, :blank, message: "can't be blank for opening balance")
      elsif amount_minor.zero?
        errors.add(:amount_minor, :zero, message: "can't be zero for opening balance")
      end
    end

    def assign_attributes_for_opening_balance
      if opening_balance_target_account.blank?
        Rails.error.report(StandardError.new("Can't save opening balance transaction without an opening balance target account"))
        throw :abort
      end

      if amount_minor.positive?
        self.src_account = Account.opening_balance_for(user: user, kind: :revenue)
        self.dest_account = opening_balance_target_account
      else
        self.src_account = opening_balance_target_account
        self.dest_account = Account.opening_balance_for(user: user, kind: :expense)
      end

      self.currency = opening_balance_target_account.currency
      self.cleared_at = transacted_at
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
