class Simplefin::Transaction < ApplicationRecord
  include Minorable
  minorable :amount, with: "account.ledger_currency"

  belongs_to :account
  has_many :transaction_sources, as: :sourceable, dependent: :destroy
  has_many :ledger_transactions, through: :transaction_sources
end
