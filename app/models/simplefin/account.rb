class Simplefin::Account < ApplicationRecord
  include Minorable
  minorable :balance, with: :ledger_currency

  belongs_to :ledger_account, class_name: "Account", optional: true
  belongs_to :connection
  has_many :transactions, dependent: :destroy

  validates :ledger_account_id, uniqueness: true, allow_nil: true

  after_update_commit :enqueue_import, if: :saved_change_to_ledger_account_id?

  def linked?
    ledger_account_id.present?
  end

  def unlinked?
    ledger_account_id.blank?
  end

  # Maps the SimpleFIN account's currency to a ledger currency.
  # This is not an association because SimpleFIN might provide a currency that is not registered in the app.
  def ledger_currency
    @ledger_currency ||= ledger_account&.currency || Currency.find_by(code: currency)
  end

  # Returns suggested opening balance attributes that align with the present SimpleFIN data.
  # Returns a hash with :amount (BigDecimal) and :transacted_at, or nil if no currency is available.
  def suggested_opening_balance
    return nil if ledger_currency.nil?

    # Find the oldest date and calculate the opening balance from SimpleFIN transactions
    amount = balance.to_d
    oldest_date = balance_date || Time.current

    transactions.each do |simplefin_transaction|
      date = [
        simplefin_transaction.transacted_at,
        simplefin_transaction.posted,
        simplefin_transaction.created_at
      ].compact.min

      oldest_date = date if date < oldest_date
      amount -= simplefin_transaction.amount.to_d
    end

    {
      amount: amount,
      transacted_at: oldest_date.beginning_of_day
    }
  end

  def enqueue_import
    TransactionImportJob.perform_later(simplefin_account_id: id)
  end
end
