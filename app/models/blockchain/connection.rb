# A self-custody wallet tracked from public chain data. The identifier is a
# single address or an extended public key; no private key or credential is
# ever stored. Unlike the bank aggregators, a user can track many wallets.
#
# The explorer it queries is the app-wide Rails.configuration.x.esplora_url,
# never a per-wallet setting (see config/initializers/blockchain.rb).
class Blockchain::Connection < ApplicationRecord
  enum :chain, { bitcoin: "bitcoin" }, validate: true

  belongs_to :user
  has_many :accounts, dependent: :destroy
  has_many :addresses, dependent: :delete_all
  has_many :transactions, through: :accounts

  # Bech32 is case-insensitive but explorers report lowercase addresses, and
  # the scanner matches addresses exactly. Base58 strings are case-sensitive.
  normalizes :identifier, with: ->(value) {
    stripped = value.strip
    stripped.downcase.start_with?("bc1", "tb1") ? stripped.downcase : stripped
  }
  normalizes :name, with: ->(value) { value.to_s.strip }

  before_validation :apply_defaults

  validates :name, :identifier, presence: true
  validates :name, length: { maximum: 100 }
  validates :identifier, uniqueness: { scope: [ :user_id, :chain ], message: "is already tracked" }
  validate :identifier_must_be_valid

  def client
    EsploraClient.new(base_url: Rails.configuration.x.esplora_url)
  end

  def refresh
    Blockchain::RefreshJob.perform_later(id)
  end

  def extended_key?
    BitcoinExtendedKey.extended_key?(identifier)
  end

  def extended_key
    BitcoinExtendedKey.parse(identifier) if extended_key?
  end

  # Shortened identifier for tables: keeps the type prefix and the tail.
  def display_identifier
    return identifier if identifier.length <= 20

    "#{identifier.first(10)}…#{identifier.last(6)}"
  end

  private

    def apply_defaults
      self.name = "Bitcoin wallet" if name.blank? && bitcoin?
    end

    def identifier_must_be_valid
      return if identifier.blank? || !bitcoin?

      if extended_key?
        key = BitcoinExtendedKey.parse(identifier)
        errors.add(:identifier, "must be a mainnet key") unless key.network == :mainnet
      else
        parsed = BitcoinAddress.parse(identifier)
        errors.add(:identifier, "must be a mainnet address") unless parsed.network == :mainnet
      end
    rescue BitcoinExtendedKey::InvalidKey, BitcoinAddress::InvalidAddress => e
      errors.add(:identifier, "is not a valid Bitcoin address or extended public key (#{e.message})")
    end
end
