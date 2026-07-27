class Simplefin::Transaction < ApplicationRecord
  include Minorable
  include AggregatorSourceable

  minorable :amount, with: "account.ledger_currency"

  belongs_to :account
  has_many :transaction_sources, as: :sourceable, dependent: :destroy
  has_many :ledger_transactions, through: :transaction_sources

  # The description the importer stores. SimpleFIN sends a single description field,
  # so this is a straight pass-through — it exists for parity with Lunch Flow, which
  # prefers its merchant field.
  def resolved_description
    description
  end
end
