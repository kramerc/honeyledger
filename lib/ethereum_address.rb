# Validates an Ethereum (EVM) account address: "0x" and 40 hex digits.
#
# Mixed case carries the EIP-55 checksum, which is the only guard against a
# typo: a mistyped address is still a valid, empty address. All-lowercase and
# all-uppercase addresses carry no checksum and are accepted as they are.
# Explorers report addresses lowercase, so that is the normalized form.
module EthereumAddress
  class InvalidAddress < StandardError; end

  FORMAT = /\A0x[0-9a-fA-F]{40}\z/
  PRIVATE_KEY_FORMAT = /\A(0x)?[0-9a-f]{64}\z/i

  # Returns the lowercase address, or raises InvalidAddress.
  def self.parse(value)
    candidate = value.to_s.strip
    if candidate.match?(PRIVATE_KEY_FORMAT)
      raise InvalidAddress, "this looks like a private key; paste the wallet's public address instead"
    end
    candidate = "0x#{candidate[2..]}" if candidate.start_with?("0X")
    raise InvalidAddress, "expected 0x followed by 40 hexadecimal characters" unless candidate.match?(FORMAT)

    digits = candidate[2..]
    if digits != digits.downcase && digits != digits.upcase && checksummed(digits.downcase) != digits
      raise InvalidAddress, "the mixed-case checksum does not match; check for a typo"
    end

    "0x#{digits.downcase}"
  end

  def self.valid?(value)
    parse(value)
    true
  rescue InvalidAddress
    false
  end

  # EIP-55: a hex letter is uppercase when the matching nibble of the
  # Keccak-256 hash of the lowercase hex string is 8 or more.
  def self.checksummed(lowercase_digits)
    hash = Keccak256.hexdigest(lowercase_digits)
    lowercase_digits.chars.each_with_index.map do |character, index|
      hash[index].to_i(16) >= 8 ? character.upcase : character
    end.join
  end
end
