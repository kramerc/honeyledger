# A self-custody wallet tracked from public chain data. The identifier is a
# single address or an extended public key; no private key or credential is
# ever stored. Unlike the bank aggregators, a user can track many wallets.
class Blockchain::Connection < ApplicationRecord
  DEFAULT_API_URLS = {
    "bitcoin" => "https://mempool.space/api"
  }.freeze

  enum :chain, { bitcoin: "bitcoin" }, validate: true

  belongs_to :user
  has_many :accounts, dependent: :destroy
  has_many :addresses, dependent: :delete_all
  has_many :transactions, through: :accounts

  normalizes :identifier, with: ->(value) { value.strip }
  normalizes :name, :api_url, with: ->(value) { value.to_s.strip }

  before_validation :apply_defaults

  validates :name, :identifier, presence: true
  validates :identifier, uniqueness: { scope: [ :user_id, :chain ], message: "is already tracked" }
  validates :api_url, format: { with: %r{\Ahttps?://\S+\z}, message: "must be an http(s) URL" }
  validate :identifier_must_be_valid

  def client
    EsploraClient.new(base_url: api_url)
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
      self.api_url = DEFAULT_API_URLS[chain] if api_url.blank? && chain.present?
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
