class Account < ApplicationRecord
  belongs_to :user
  belongs_to :currency, optional: true

  # Initialize the balance except for virtual accounts, as those don't have balances.
  before_create -> { self.balance_minor = self.balance_minor.to_i }, unless: :virtual?

  # Transactions (source, destination, opening balance)
  before_destroy -> { opening_balance_transaction.destroy! }, if: -> { opening_balance_transaction.present? && empty? }
  has_many :src_transactions, class_name: "Transaction", foreign_key: "src_account_id", dependent: :restrict_with_error
  has_many :dest_transactions, class_name: "Transaction", foreign_key: "dest_account_id", dependent: :restrict_with_error
  before_validation :assign_opening_balance_transaction_attributes, if: :opening_balance_callback_needed?
  validate :opening_balance_not_allowed_for_kind, if: :opening_balance_callback_needed?
  validate :opening_balance_transaction_is_valid, if: :opening_balance_callback_needed?
  after_save :save_or_destroy_opening_balance_transaction, if: :opening_balance_callback_needed?

  has_one :simplefin_account, class_name: "Simplefin::Account", foreign_key: :ledger_account_id, dependent: :nullify

  enum :kind, %i[ asset liability equity expense revenue ]
  SOURCEABLE = %i[ asset liability equity revenue ].freeze
  DESTINABLE = %i[ asset liability equity expense ].freeze
  scope :sourceable, -> { where(kind: SOURCEABLE).real }
  scope :destinable, -> { where(kind: DESTINABLE).real }

  validates :currency, presence: true, unless: :virtual?
  validates :name, presence: true

  scope :real, -> { where(virtual: false) }
  scope :virtual, -> { where(virtual: true) }
  scope :linkable, -> { where(kind: %i[ asset liability ]) }
  scope :unlinked, -> { left_joins(:simplefin_account).where(simplefin_accounts: { id: nil }) }

  def self.opening_balance_for(user:, kind:)
    attributes = { user: user, kind: kind, name: "Opening Balance", virtual: true }
    Account.find_or_create_by!(attributes)
  rescue ActiveRecord::RecordNotUnique
    Account.find_by(attributes) || raise
  end

  def build_opening_balance_transaction(transaction_attributes = {})
    @opening_balance_transaction = Transaction.new({
      user: user,
      currency: currency,
      opening_balance: true
    }.merge(transaction_attributes))
  end

  def opening_balance_transaction
    @opening_balance_transaction ||= Transaction.where(src_account: self)
      .or(Transaction.where(dest_account: self))
      .opening_balances
      .first
  end

  # Virtual attributes for the opening balance form fields.
  # Reading derives the signed amount from the persisted transaction so the form pre-fills correctly.
  attr_writer :opening_balance_amount, :opening_balance_transacted_at

  def opening_balance_amount
    return @opening_balance_amount if instance_variable_defined?(:@opening_balance_amount)
    return nil unless opening_balance_transaction
    t = opening_balance_transaction
    t.src_account&.real? ? -t.amount : t.amount
  end

  def opening_balance_transacted_at
    return @opening_balance_transacted_at if instance_variable_defined?(:@opening_balance_transacted_at)
    opening_balance_transaction&.transacted_at
  end

  def reset_balance
    return false if virtual?

    deposits = Transaction.where(dest_account: self).sum(:amount_minor)
    withdrawals = Transaction.where(src_account: self).sum("COALESCE(fx_amount_minor, amount_minor)")
    update_column(:balance_minor, deposits - withdrawals)
  end

  def empty?
    count = Transaction.where(src_account: self).or(Transaction.where(dest_account: self)).count
    count -= 1 if opening_balance_transaction.present?
    count.zero?
  end

  def real?
    !virtual?
  end

  # Returns the opening balance amount in minor units with the correct sign for display.
  # Since opening balance transactions always store a positive amount_minor, the direction
  # is re-derived from whether the real account is the source (negative) or destination (positive).
  def opening_balance_amount_minor
    return nil unless opening_balance_transaction
    t = opening_balance_transaction
    t.src_account&.real? ? -t.amount_minor.to_i : t.amount_minor
  end

  # Check if a user has access to this account
  # Currently checks ownership, but can be extended for sharing
  def accessible_by?(user)
    user_id == user.id
  end

  private

    def opening_balance_not_allowed_for_kind
      # Only block when the user is actively supplying an amount — existing
      # transactions on unusual accounts (bug data) should not prevent saving.
      return unless expense? || revenue?
      return unless instance_variable_defined?(:@opening_balance_amount) && @opening_balance_amount.present?

      errors.add(:opening_balance_amount, "is not allowed for #{kind} accounts")
    end

    def opening_balance_callback_needed?
      # Always run if there is already an opening balance transaction to maintain.
      return true if opening_balance_transaction.present?

      # Otherwise only run if a meaningful (non-blank, non-zero) amount is provided.
      return false unless instance_variable_defined?(:@opening_balance_amount)

      raw_amount = @opening_balance_amount
      return false if raw_amount.blank?

      amount_decimal = begin
        BigDecimal(raw_amount)
      rescue ArgumentError, TypeError
        # Unparseable input (e.g. "hello"): let validations handle it.
        return true
      end

      !amount_decimal.zero?
    end

    def assign_opening_balance_transaction_attributes
      t = opening_balance_transaction || build_opening_balance_transaction
      t.user = user
      t.currency = currency
      t.opening_balance = true

      # Set transacted_at first so it's present even when we return early for blank/zero amounts
      t.transacted_at = @opening_balance_transacted_at if instance_variable_defined?(:@opening_balance_transacted_at)

      if instance_variable_defined?(:@opening_balance_amount)
        t.amount = @opening_balance_amount
        amount_decimal = begin; BigDecimal(@opening_balance_amount); rescue ArgumentError, TypeError; nil; end
        # Blank/zero: transaction will be destroyed in after_save; skip account assignment
        return if @opening_balance_amount.blank? || (amount_decimal && amount_decimal.zero?)
        # Unparseable (e.g. "hello"): leave raw amount so Minorable validates it; skip account assignment
        return if amount_decimal.nil?
        negative = amount_decimal.negative?
        t.amount = amount_decimal.abs
      else
        # Derive direction from the existing account roles. Amount_minor is now
        # always stored as a positive value so its sign cannot be used.
        negative = t.src_account_id == id
        t.amount_minor = t.amount_minor.to_i.abs
        return if t.amount_minor.zero?
      end

      t.cleared_at = t.transacted_at

      if negative
        t.src_account = self
        t.dest_account = Account.opening_balance_for(user: user, kind: :expense)
      else
        t.src_account = Account.opening_balance_for(user: user, kind: :revenue)
        t.dest_account = self
      end
    end

    def opening_balance_transaction_is_valid
      unless opening_balance_transaction.valid?
        opening_balance_transaction.errors.each do |error|
          account_attribute = case error.attribute
          when :amount, :amount_minor then :opening_balance_amount
          when :transacted_at then :opening_balance_transacted_at
          else :"opening_balance_transaction.#{error.attribute}"
          end

          errors.add(account_attribute, error.message)
        end
      end
    end

    def save_or_destroy_opening_balance_transaction
      should_destroy = if opening_balance_transaction.amount_written?
        opening_balance_transaction.amount.to_d.zero?
      else
        opening_balance_transaction.amount_minor.to_i.zero?
      end

      if should_destroy
        opening_balance_transaction.destroy! if opening_balance_transaction.persisted?
        @opening_balance_transaction = nil
      else
        opening_balance_transaction.save!
      end
    end
end
