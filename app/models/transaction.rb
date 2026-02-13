class Transaction < ApplicationRecord
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
  before_save :set_amount_minor_from_amount
  before_save :set_fx_amount_minor_from_fx_amount

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?

  scope :opening_balances, -> { where(opening_balance: true) }

  attr_writer :amount, :fx_amount
  validate :virtual_amounts_numericality
  validate :src_account_accessible_to_user
  validate :dest_account_accessible_to_user

  def cleared
    return @cleared if defined?(@cleared)
    cleared_at.present?
  end

  def cleared=(value)
    @cleared = ActiveModel::Type::Boolean.new.cast(value)
  end

  def amount_minor=(value)
    super(value)
    @amount = nil
  end

  def amount
    return @amount if @amount.present?
    return nil unless amount_minor && currency

    BigDecimal(amount_minor) / (10**currency.decimal_places)
  end

  def fx_amount_minor=(value)
    super(value)
    @fx_amount = nil
  end

  def fx_amount
    return @fx_amount if @fx_amount.present?
    return nil unless fx_amount_minor && fx_currency

    BigDecimal(fx_amount_minor) / (10**fx_currency.decimal_places)
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

  def set_amount_minor_from_amount
    return unless @amount && currency

    self.amount_minor = (@amount.to_d * (10**currency.decimal_places)).round.to_i
  end

  def set_fx_amount_minor_from_fx_amount
    return unless @fx_amount && fx_currency

    self.fx_amount_minor = (@fx_amount.to_d * (10**fx_currency.decimal_places)).round.to_i
  end

  def virtual_amounts_numericality
    if @amount.present? && !numeric?(@amount)
      errors.add(:amount, "must be a valid number")
    end

    if @fx_amount.present? && !numeric?(@fx_amount)
      errors.add(:fx_amount, "must be a valid number")
    end
  end

  def mark_parent_as_split
    parent_transaction.update(split: true)
  end

  def unmark_parent_if_last_child
    parent_transaction.update(split: false) if parent_transaction.child_transactions.empty?
  end

  def numeric?(value)
    BigDecimal(value)
    true
  rescue ArgumentError, TypeError
    false
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
end
