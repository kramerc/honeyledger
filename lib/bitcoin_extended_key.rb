require "openssl"

# A BIP32 extended *public* key (xpub, ypub, zpub, or their testnet forms) and
# the addresses derived from it.
#
# Only public child derivation is implemented: there is no code path that
# accepts, derives, or stores a private key. An extended private key is
# recognised only so it can be refused with a clear message.
class BitcoinExtendedKey
  class InvalidKey < StandardError; end

  # Version bytes (SLIP-0132) → network and the script type the wallet uses.
  PUBLIC_VERSIONS = {
    "0488b21e" => { prefix: "xpub", network: :mainnet, script: :p2pkh },
    "049d7cb2" => { prefix: "ypub", network: :mainnet, script: :p2sh_p2wpkh },
    "04b24746" => { prefix: "zpub", network: :mainnet, script: :p2wpkh },
    "043587cf" => { prefix: "tpub", network: :testnet, script: :p2pkh },
    "044a5262" => { prefix: "upub", network: :testnet, script: :p2sh_p2wpkh },
    "045f1cf6" => { prefix: "vpub", network: :testnet, script: :p2wpkh }
  }.freeze

  PRIVATE_VERSIONS = %w[0488ade4 049d7878 04b2430c 04358394 044a4e28 045f18bc].freeze

  HARDENED = 0x80000000

  GROUP = OpenSSL::PKey::EC::Group.new("secp256k1")

  attr_reader :network, :script, :depth, :chain_code, :public_key

  def self.parse(string)
    payload = BitcoinAddress.base58check_decode(string.to_s.strip)
    raise InvalidKey, "Extended key has the wrong length" unless payload.bytesize == 78

    version = payload.byteslice(0, 4).unpack1("H*")
    if PRIVATE_VERSIONS.include?(version)
      raise InvalidKey, "That is an extended private key. Only paste the public key (xpub, ypub, or zpub)."
    end

    details = PUBLIC_VERSIONS[version]
    raise InvalidKey, "Unsupported extended key version" if details.nil?

    new(
      version: version,
      depth: payload.getbyte(4),
      parent_fingerprint: payload.byteslice(5, 4),
      child_number: payload.byteslice(9, 4).unpack1("N"),
      chain_code: payload.byteslice(13, 32),
      public_key: payload.byteslice(45, 33)
    )
  rescue BitcoinAddress::InvalidAddress => e
    raise InvalidKey, e.message
  end

  # Whether the string is shaped like an extended key. Private forms (xprv…)
  # match too, so they reach +parse+ and its explicit refusal instead of being
  # misread as a malformed address.
  def self.extended_key?(string)
    string.to_s.strip.match?(/\A[xyztuv](pub|prv)[1-9A-HJ-NP-Za-km-z]{100,}\z/)
  end

  def initialize(version:, depth:, parent_fingerprint:, child_number:, chain_code:, public_key:)
    details = PUBLIC_VERSIONS.fetch(version)
    @version = version
    @network = details[:network]
    @script = details[:script]
    @depth = depth
    @parent_fingerprint = parent_fingerprint
    @child_number = child_number
    @chain_code = chain_code
    @public_key = public_key
    point # validates the key is on the curve
  end

  # Public child key derivation (CKDpub). Hardened indexes are impossible from a
  # public key by construction.
  def child(index)
    raise InvalidKey, "Cannot derive a hardened child from a public key" if index >= HARDENED

    digest = OpenSSL::HMAC.digest("SHA512", chain_code, public_key + [ index ].pack("N"))
    tweak = OpenSSL::BN.new(digest.byteslice(0, 32), 2)
    raise InvalidKey, "Derived key is invalid; skip this index" if tweak >= GROUP.order

    child_point = GROUP.generator.mul(tweak).add(point)
    raise InvalidKey, "Derived key is invalid; skip this index" if child_point.infinity?

    self.class.new(
      version: @version,
      depth: depth + 1,
      parent_fingerprint: BitcoinAddress.hash160(public_key).byteslice(0, 4),
      child_number: index,
      chain_code: digest.byteslice(32, 32),
      public_key: child_point.to_octet_string(:compressed)
    )
  end

  # Derives along a non-hardened path, e.g. derive(0, 5) for receive address 5.
  def derive(*indexes)
    indexes.reduce(self) { |key, index| key.child(index) }
  end

  # The address of this key under the wallet's script type.
  def address
    BitcoinAddress.public_send(script, public_key, network: network)
  end

  # Address at branch/index below this account key: branch 0 receives, 1 is change.
  def address_at(branch, index)
    derive(branch, index).address
  end

  def to_s
    payload = [ @version ].pack("H*") + depth.chr + @parent_fingerprint + [ @child_number ].pack("N") + chain_code + public_key
    BitcoinAddress.base58check_encode(payload)
  end

  private

    def point
      @point ||= OpenSSL::PKey::EC::Point.new(GROUP, OpenSSL::BN.new(public_key, 2))
    rescue OpenSSL::PKey::EC::Point::Error
      raise InvalidKey, "Extended key does not contain a valid public key"
    end
end
