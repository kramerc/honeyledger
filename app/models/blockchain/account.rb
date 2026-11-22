# One asset held by a tracked wallet. A Bitcoin wallet has exactly one (BTC).
class Blockchain::Account < ApplicationRecord
  include Minorable
  include AggregatorLinkable

  minorable :balance, with: :ledger_currency

  has_many :transactions, dependent: :destroy

  validates :remote_id, presence: true, uniqueness: { scope: :connection_id }

  def current?(threshold = connection&.refreshed_at)
    return false if last_seen_at.nil?
    return false if threshold.nil?

    last_seen_at >= threshold
  end

  # The wallet's label stands in for an institution on the integrations page.
  def institution_name
    connection&.name
  end

  def ledger_currency
    @ledger_currency ||= ledger_account&.currency || Currency.find_by(code: currency)
  end

  # Chain history is complete back to the wallet's first transaction, so walking
  # the balance back through every row normally lands on zero: the import alone
  # reproduces the balance and no opening balance is needed.
  def suggested_opening_balance
    return nil if ledger_currency.nil?

    amount = balance.to_d
    oldest_time = Time.current

    transactions.confirmed.each do |blockchain_transaction|
      time = blockchain_transaction.transacted_at || blockchain_transaction.created_at
      oldest_time = time if time < oldest_time
      amount -= blockchain_transaction.signed_ledger_amount
    end

    {
      amount: amount,
      transacted_at: oldest_time.beginning_of_day
    }
  end
end
