class Lunchflow::Account < ApplicationRecord
  include Minorable
  minorable :balance, with: :ledger_currency

  has_one :ledger_account, class_name: "Account", as: :sourceable, dependent: :nullify

  belongs_to :connection
  has_many :transactions, dependent: :destroy

  validates :remote_id, uniqueness: { scope: :connection_id }

  def linked?
    ledger_account.present?
  end

  def unlinked?
    ledger_account.blank?
  end

  # Maps the Lunch Flow account's currency to a ledger currency.
  def ledger_currency
    @ledger_currency ||= ledger_account&.currency || Currency.find_by(code: currency)
  end

  # Returns suggested opening balance attributes that align with the present Lunch Flow data.
  # Returns a hash with :amount (BigDecimal) and :transacted_at, or nil if no currency is available.
  def suggested_opening_balance
    return nil if ledger_currency.nil?

    amount = balance.to_d
    oldest_date = Date.current

    transactions.each do |lf_transaction|
      date = lf_transaction.date || lf_transaction.created_at.to_date
      oldest_date = date if date < oldest_date
      amount -= lf_transaction.amount.to_d
    end

    {
      amount: amount,
      transacted_at: oldest_date.beginning_of_day
    }
  end
end
