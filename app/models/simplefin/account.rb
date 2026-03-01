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

  # Builds an opening balance transaction that aligns with the present SimpleFIN data
  def build_opening_balance_ledger_transaction(params = {})
    return nil if ledger_currency.nil?

    ledger_transaction = Transaction.new({
      currency: ledger_currency,
      amount_minor: balance_minor
    }.merge(params))

    oldest_simplefin_transaction = nil
    oldest_date = Time.current
    transactions.all.each do |simplefin_transaction|
      date = [
        simplefin_transaction.transacted_at,
        simplefin_transaction.posted,
        simplefin_transaction.created_at
      ].compact.min

      if oldest_simplefin_transaction.nil? || date < oldest_date
        oldest_simplefin_transaction = simplefin_transaction
        oldest_date = date
      end

      ledger_transaction.amount_minor -= simplefin_transaction.amount_minor
    end

    ledger_transaction.transacted_at = oldest_date.beginning_of_day
    ledger_transaction
  end

  def enqueue_import
    TransactionImportJob.perform_later(simplefin_account_id: id)
  end
end
