require "test_helper"

# Vectors are copied from BIP173 and BIP350.
class BitcoinAddressTest < ActiveSupport::TestCase
  GENERATOR_PUBLIC_KEY = [ "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" ].pack("H*")

  test "encodes P2WPKH for the BIP173 example key" do
    assert_equal "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", BitcoinAddress.p2wpkh(GENERATOR_PUBLIC_KEY)
  end

  test "hash160 matches the BIP173 witness program" do
    assert_equal "751e76e8199196d454941c45d1b3a323f1433bd6", BitcoinAddress.hash160(GENERATOR_PUBLIC_KEY).unpack1("H*")
  end

  test "parses valid SegWit addresses from BIP350" do
    assert_equal BitcoinAddress::Parsed.new(network: :mainnet, type: :p2wpkh), BitcoinAddress.parse("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4")
    assert_equal BitcoinAddress::Parsed.new(network: :mainnet, type: :p2tr), BitcoinAddress.parse("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0")
    assert_equal BitcoinAddress::Parsed.new(network: :testnet, type: :p2tr), BitcoinAddress.parse("tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c")
  end

  test "rejects invalid SegWit addresses from BIP350" do
    [
      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd", # Bech32 checksum on v1
      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh",                     # Bech32m checksum on v0
      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav253zgeav", # 41-byte program
      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf" # excess padding
    ].each do |address|
      assert_raises(BitcoinAddress::InvalidAddress, address) { BitcoinAddress.parse(address) }
    end
  end

  test "parses legacy addresses and detects bad checksums" do
    p2pkh = BitcoinAddress.p2pkh(GENERATOR_PUBLIC_KEY)
    p2sh = BitcoinAddress.p2sh_p2wpkh(GENERATOR_PUBLIC_KEY)

    assert_equal "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", p2pkh
    assert_equal BitcoinAddress::Parsed.new(network: :mainnet, type: :p2pkh), BitcoinAddress.parse(p2pkh)
    assert_equal BitcoinAddress::Parsed.new(network: :mainnet, type: :p2sh), BitcoinAddress.parse(p2sh)
    assert_raises(BitcoinAddress::InvalidAddress) { BitcoinAddress.parse(p2pkh.sub(/H\z/, "J")) }
  end

  test "classifies other witness programs" do
    p2wsh = BitcoinAddress.segwit_encode("bc", 0, "\x01".b * 32)
    future_version = BitcoinAddress.segwit_encode("bc", 2, "\x01".b * 16)

    assert_equal :p2wsh, BitcoinAddress.parse(p2wsh).type
    assert_equal :witness_unknown, BitcoinAddress.parse(future_version).type
  end

  test "rejects malformed addresses" do
    {
      "a v0 program that is neither 20 nor 32 bytes" => BitcoinAddress.segwit_encode("bc", 0, "\x01".b * 25),
      "mixed case" => "bc1qW508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
      "too short to hold a checksum" => "bc1qqqq",
      "a checksum mismatch" => "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5",
      "an unknown Base58 version" => BitcoinAddress.base58check_encode("\x30".b + "\x01".b * 20)
    }.each do |reason, address|
      assert_raises(BitcoinAddress::InvalidAddress, reason) { BitcoinAddress.parse(address) }
    end
  end

  test "valid? checks the network" do
    assert BitcoinAddress.valid?("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    assert_not BitcoinAddress.valid?("tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c")
    assert_not BitcoinAddress.valid?("not an address")
  end
end
