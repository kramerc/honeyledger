class Csv::Transaction < ApplicationRecord
  belongs_to :import, class_name: "Csv::Import"
  has_many :transaction_sources, as: :sourceable, dependent: :destroy
  has_many :ledger_transactions, through: :transaction_sources

  delegate :user, :account, to: :import
end
