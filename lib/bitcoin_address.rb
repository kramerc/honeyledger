require "openssl"

# Encodes and validates Bitcoin addresses using only the standard library.
#
# Covers the address types a watch-only wallet needs: legacy P2PKH and P2SH
# (Base58Check), and native SegWit v0 (Bech32, BIP173) and v1+ such as Taproot
# (Bech32m, BIP350). Nothing here touches private keys.
module BitcoinAddress
  class InvalidAddress < StandardError; end

  NETWORKS = {
    mainnet: { p2pkh: 0x00, p2sh: 0x05, hrp: "bc" },
    testnet: { p2pkh: 0x6f, p2sh: 0xc4, hrp: "tb" }
  }.freeze

  BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze
  BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".freeze
  BECH32_CONSTANT = 1
  BECH32M_CONSTANT = 0x2bc830a3

  # Result of parsing an address: its network and output type.
  Parsed = Data.define(:network, :type)

  module_function

  def hash160(bytes)
    OpenSSL::Digest.new("RIPEMD160").digest(OpenSSL::Digest::SHA256.digest(bytes))
  end

  def p2pkh(public_key, network: :mainnet)
    base58check_encode(NETWORKS.fetch(network)[:p2pkh].chr + hash160(public_key))
  end

  # P2WPKH nested in P2SH (BIP49 "ypub" wallets).
  def p2sh_p2wpkh(public_key, network: :mainnet)
    redeem_script = "\x00\x14".b + hash160(public_key)
    base58check_encode(NETWORKS.fetch(network)[:p2sh].chr + hash160(redeem_script))
  end

  # Native SegWit v0 (BIP84 "zpub" wallets).
  def p2wpkh(public_key, network: :mainnet)
    segwit_encode(NETWORKS.fetch(network)[:hrp], 0, hash160(public_key))
  end

  # Parses an address and returns its network and type, or raises InvalidAddress.
  def parse(address)
    address = address.to_s.strip
    raise InvalidAddress, "Address is blank" if address.empty?

    if address.downcase.start_with?("bc1", "tb1")
      parse_segwit(address)
    else
      parse_base58(address)
    end
  end

  def valid?(address, network: :mainnet)
    parse(address).network == network
  rescue InvalidAddress
    false
  end

  # -- Base58Check ------------------------------------------------------------

  def base58check_encode(payload)
    base58_encode(payload + checksum(payload))
  end

  def base58check_decode(string)
    bytes = base58_decode(string)
    raise InvalidAddress, "Base58 payload is too short" if bytes.bytesize < 5

    payload = bytes.byteslice(0, bytes.bytesize - 4)
    raise InvalidAddress, "Base58 checksum mismatch" unless checksum(payload) == bytes.byteslice(-4, 4)

    payload
  end

  def base58_encode(bytes)
    number = bytes.unpack1("H*").then { |hex| hex.empty? ? 0 : hex.to_i(16) }
    encoded = +""
    while number.positive?
      number, remainder = number.divmod(58)
      encoded.prepend(BASE58_ALPHABET[remainder])
    end
    leading_zeros = bytes.each_byte.take_while(&:zero?).size
    ("1" * leading_zeros) + encoded
  end

  def base58_decode(string)
    number = string.each_char.reduce(0) do |accumulator, character|
      index = BASE58_ALPHABET.index(character)
      raise InvalidAddress, "Invalid Base58 character" if index.nil?

      accumulator * 58 + index
    end
    hex = number.zero? ? "" : number.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    leading_zeros = string.each_char.take_while { |character| character == "1" }.size
    ("\x00" * leading_zeros).b + [ hex ].pack("H*")
  end

  def checksum(payload)
    OpenSSL::Digest::SHA256.digest(OpenSSL::Digest::SHA256.digest(payload)).byteslice(0, 4)
  end

  def parse_base58(address)
    payload = base58check_decode(address)
    raise InvalidAddress, "Base58 address has the wrong length" unless payload.bytesize == 21

    version = payload.getbyte(0)
    NETWORKS.each do |network, prefixes|
      return Parsed.new(network: network, type: :p2pkh) if version == prefixes[:p2pkh]
      return Parsed.new(network: network, type: :p2sh) if version == prefixes[:p2sh]
    end
    raise InvalidAddress, "Unknown address version"
  end

  # -- Bech32 / Bech32m -------------------------------------------------------

  def segwit_encode(hrp, witness_version, program)
    constant = witness_version.zero? ? BECH32_CONSTANT : BECH32M_CONSTANT
    data = [ witness_version ] + convert_bits(program.bytes, 8, 5, pad: true)
    bech32_encode(hrp, data, constant)
  end

  def parse_segwit(address)
    if address != address.downcase && address != address.upcase
      raise InvalidAddress, "Mixed-case Bech32 address"
    end

    hrp, data, constant = bech32_decode(address.downcase)
    network = NETWORKS.find { |_name, prefixes| prefixes[:hrp] == hrp }&.first
    raise InvalidAddress, "Unknown address prefix" if network.nil?
    raise InvalidAddress, "Empty witness data" if data.empty?

    witness_version = data.first
    raise InvalidAddress, "Invalid witness version" if witness_version > 16

    program = convert_bits(data.drop(1), 5, 8, pad: false)
    raise InvalidAddress, "Invalid witness program length" unless program.size.between?(2, 40)

    expected_constant = witness_version.zero? ? BECH32_CONSTANT : BECH32M_CONSTANT
    raise InvalidAddress, "Wrong checksum variant for witness version" unless constant == expected_constant

    type =
      if witness_version.zero?
        case program.size
        when 20 then :p2wpkh
        when 32 then :p2wsh
        else raise InvalidAddress, "Invalid v0 witness program length"
        end
      elsif witness_version == 1 && program.size == 32
        :p2tr
      else
        :witness_unknown
      end

    Parsed.new(network: network, type: type)
  end

  def bech32_encode(hrp, data, constant)
    polymod = bech32_polymod(hrp_expand(hrp) + data + [ 0 ] * 6) ^ constant
    checksum = Array.new(6) { |index| (polymod >> (5 * (5 - index))) & 31 }
    hrp + "1" + (data + checksum).map { |value| BECH32_CHARSET[value] }.join
  end

  # Returns [hrp, data (without checksum), checksum constant].
  def bech32_decode(string)
    raise InvalidAddress, "Bech32 address is too long" if string.length > 90

    separator = string.rindex("1")
    if separator.nil? || separator < 1 || separator + 7 > string.length
      raise InvalidAddress, "Malformed Bech32 address"
    end

    hrp = string[0...separator]
    data = string[(separator + 1)..].each_char.map do |character|
      BECH32_CHARSET.index(character) || raise(InvalidAddress, "Invalid Bech32 character")
    end

    constant = bech32_polymod(hrp_expand(hrp) + data)
    unless [ BECH32_CONSTANT, BECH32M_CONSTANT ].include?(constant)
      raise InvalidAddress, "Bech32 checksum mismatch"
    end

    [ hrp, data[0...-6], constant ]
  end

  def bech32_polymod(values)
    generator = [ 0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3 ]
    values.reduce(1) do |checksum, value|
      top = checksum >> 25
      checksum = ((checksum & 0x1ffffff) << 5) ^ value
      5.times { |bit| checksum ^= generator[bit] if (top >> bit) & 1 == 1 }
      checksum
    end
  end

  def hrp_expand(hrp)
    hrp.each_char.map { |character| character.ord >> 5 } + [ 0 ] + hrp.each_char.map { |character| character.ord & 31 }
  end

  def convert_bits(values, from_bits, to_bits, pad:)
    accumulator = 0
    bits = 0
    result = []
    max_value = (1 << to_bits) - 1
    values.each do |value|
      raise InvalidAddress, "Invalid data value" if value.negative? || (value >> from_bits).positive?

      accumulator = (accumulator << from_bits) | value
      bits += from_bits
      while bits >= to_bits
        bits -= to_bits
        result << ((accumulator >> bits) & max_value)
      end
    end

    if pad
      result << ((accumulator << (to_bits - bits)) & max_value) if bits.positive?
    elsif bits >= from_bits || ((accumulator << (to_bits - bits)) & max_value).positive?
      raise InvalidAddress, "Invalid padding"
    end

    result
  end
end
