class SimplefinTransaction < ApplicationRecord
  belongs_to :simplefin_account
  has_one :ledger_transaction, class_name: "Transaction", as: :sourceable, dependent: :nullify

  def amount_minor
    currency = simplefin_account.account.currency
    (BigDecimal(amount) * 10**currency.decimal_places).to_i
  end
end
