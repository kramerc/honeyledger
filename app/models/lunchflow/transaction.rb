class Lunchflow::Transaction < ApplicationRecord
  include Minorable
  minorable :amount, with: "account.ledger_currency"

  belongs_to :account
  has_one :ledger_transaction, class_name: "Transaction", as: :sourceable, dependent: :nullify

  validates :remote_id, uniqueness: { scope: :account_id }, allow_nil: true
end
