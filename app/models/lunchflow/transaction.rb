class Lunchflow::Transaction < ApplicationRecord
  include Minorable
  include AggregatorSourceable

  minorable :amount, with: "account.ledger_currency"

  belongs_to :account
  has_many :transaction_sources, as: :sourceable, dependent: :destroy
  has_many :ledger_transactions, through: :transaction_sources

  validates :remote_id, uniqueness: { scope: :account_id }, allow_nil: true

  # The description the importer stores. Lunch Flow's merchant is the cleaner label
  # when present, so it wins over the raw description.
  def resolved_description
    merchant.presence || description
  end
end
