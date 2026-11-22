# A wallet-relative movement on chain. Each on-chain transaction the wallet
# took part in becomes one "transfer" row (remote_id = txid) carrying the net
# amount excluding the fee, plus a "fee" row (remote_id = "<txid>:fee") when
# the wallet funded it. The two import as separate ledger transactions so the
# fee lands on its own expense account and the transfer leg stays matchable.
class Blockchain::Transaction < ApplicationRecord
  include Minorable
  include AggregatorSourceable

  enum :kind, { transfer: "transfer", fee: "fee" }, validate: true

  minorable :amount, with: "account.ledger_currency"

  belongs_to :account
  has_many :transaction_sources, as: :sourceable, dependent: :destroy
  has_many :ledger_transactions, through: :transaction_sources

  validates :remote_id, presence: true, uniqueness: { scope: :account_id }

  scope :confirmed, -> { where(confirmed: true) }

  # The description the importer stores. The full counterparty address is kept
  # so an import rule can match a known address (an exchange deposit address,
  # say) and route the transfer to the right account.
  def resolved_description
    if fee?
      "#{asset_name} network fee"
    elsif amount.to_d.negative?
      counterparty.present? ? "Sent to #{counterparty}" : "#{asset_name} sent"
    else
      counterparty.present? ? "Received from #{counterparty}" : "#{asset_name} received"
    end
  end

  private

    def asset_name
      account&.name.presence || "Crypto"
    end
end
