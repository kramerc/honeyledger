# A self-custody wallet tracked from public chain data. The identifier is a
# single address or (Bitcoin only) an extended public key; no private key or
# credential is ever stored. Unlike the bank aggregators, a user can track
# many wallets.
#
# The explorer each chain queries is app-wide configuration, never a
# per-wallet setting (see config/initializers/blockchain.rb).
class Blockchain::Connection < ApplicationRecord
  enum :chain, { bitcoin: "bitcoin", ethereum: "ethereum" }, validate: true

  DEFAULT_NAMES = { "bitcoin" => "Bitcoin wallet", "ethereum" => "Ethereum wallet" }.freeze

  belongs_to :user
  has_many :accounts, dependent: :destroy
  has_many :addresses, dependent: :delete_all
  has_many :transactions, through: :accounts

  # Explorers report Bech32 and Ethereum addresses lowercase, and the scanners
  # match addresses exactly. Base58 strings are case-sensitive and kept as is.
  normalizes :identifier, with: ->(value) {
    stripped = value.strip
    stripped.downcase.start_with?("bc1", "tb1", "0x") ? stripped.downcase : stripped
  }
  normalizes :name, with: ->(value) { value.to_s.strip }

  before_validation :apply_defaults

  validates :name, :identifier, presence: true
  validates :name, length: { maximum: 100 }
  validates :identifier, uniqueness: { scope: [ :user_id, :chain ], message: "is already tracked" }
  validate :identifier_must_be_valid
  validate :chain_must_be_available, on: :create

  # Whether this server is configured to track wallets on the chain. Bitcoin's
  # explorer is keyless; Ethereum's needs an operator API key.
  def self.chain_available?(chain)
    case chain.to_s
    when "bitcoin" then true
    when "ethereum"
      settings = Rails.configuration.x.evm_explorer
      settings[:api_key].present? && EvmExplorerClient.known_provider?(settings[:provider])
    else false
    end
  end

  def self.available_chains
    chains.keys.select { |chain| chain_available?(chain) }
  end

  # The address as typed, before normalization lowercased it: its mixed case
  # carries the EIP-55 checksum, which only validation reads.
  def identifier=(value)
    @identifier_as_entered = value
    super
  end

  def client
    if ethereum?
      settings = Rails.configuration.x.evm_explorer
      EvmExplorerClient.new(provider: settings[:provider], base_url: settings[:base_url], api_key: settings[:api_key],
        chain_id: EvmExplorerClient::ETHEREUM_MAINNET)
    else
      EsploraClient.new(base_url: Rails.configuration.x.esplora_url)
    end
  end

  def refresh
    Blockchain::RefreshJob.perform_later(id)
  end

  def extended_key?
    bitcoin? && BitcoinExtendedKey.extended_key?(identifier)
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
      self.name = DEFAULT_NAMES[chain] if name.blank? && DEFAULT_NAMES.key?(chain)
    end

    def identifier_must_be_valid
      return if identifier.blank?

      if bitcoin?
        bitcoin_identifier_must_be_valid
      elsif ethereum?
        ethereum_identifier_must_be_valid
      end
    end

    def bitcoin_identifier_must_be_valid
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

    def ethereum_identifier_must_be_valid
      EthereumAddress.parse(identifier_changed? && @identifier_as_entered.is_a?(String) ? @identifier_as_entered : identifier)
    rescue EthereumAddress::InvalidAddress => e
      errors.add(:identifier, "is not a valid Ethereum address (#{e.message})")
    end

    def chain_must_be_available
      return if chain.blank? || !self.class.chains.key?(chain)

      errors.add(:base, "#{chain.titleize} wallets are not configured on this server") unless self.class.chain_available?(chain)
    end
end
