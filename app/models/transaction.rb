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

  after_create :mark_parent_as_split, if: :parent_transaction_id?
  after_destroy :unmark_parent_if_last_child, if: :parent_transaction_id?

  scope :opening_balances, -> { where(opening_balance: true) }

  def amount
    BigDecimal(amount_minor) / (10**currency.decimal_places)
  end

  def amount=(value)
    self.amount_minor = (BigDecimal(value.to_s) * (10**currency.decimal_places)).round.to_i
  end

  def fx_amount
    return nil unless fx_amount_minor && fx_currency

    BigDecimal(fx_amount_minor) / (10**fx_currency.decimal_places)
  end

  def fx_amount=(value)
    self.fx_amount_minor = (BigDecimal(value.to_s) * (10**fx_currency.decimal_places)).round.to_i
  end

  def has_fx?
    fx_amount_minor.present? && fx_currency.present?
  end

  private

  def set_currency_from_dest_account
    self.currency_id = dest_account.currency_id if dest_account.present?
  end

  def mark_parent_as_split
    parent_transaction.update(split: true)
  end

  def unmark_parent_if_last_child
    parent_transaction.update(split: false) if parent_transaction.child_transactions.empty?
  end
end
