require "test_helper"

class EthereumAddressTest < ActiveSupport::TestCase
  # The checksummed examples published in EIP-55.
  EIP55_EXAMPLES = %w[
    0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
    0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359
    0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB
    0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb
  ].freeze

  test "accepts checksummed addresses and returns them lowercase" do
    EIP55_EXAMPLES.each do |address|
      assert_equal address.downcase, EthereumAddress.parse(address)
      assert_equal address[2..], EthereumAddress.checksummed(address[2..].downcase)
    end
  end

  test "accepts all-lowercase and all-uppercase addresses, which carry no checksum" do
    assert_equal "0xde709f2102306220921060314715629080e2fb77", EthereumAddress.parse("0xde709f2102306220921060314715629080e2fb77")
    assert_equal "0x52908400098527886e0f7030069857d2e4169ee7", EthereumAddress.parse("0x52908400098527886E0F7030069857D2E4169EE7")
    assert_equal "0x52908400098527886e0f7030069857d2e4169ee7", EthereumAddress.parse(" 0X52908400098527886E0F7030069857D2E4169EE7\n")
  end

  test "rejects a mixed-case address whose checksum does not match" do
    error = assert_raises(EthereumAddress::InvalidAddress) { EthereumAddress.parse("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD") }

    assert_match(/checksum/, error.message)
  end

  test "rejects malformed input" do
    [ "", "0x123", "5aaeb6053f3e94c9b9a09f33669435e7ef1beaed", "0xZZaeb6053f3e94c9b9a09f33669435e7ef1beaed", "vitalik.eth" ].each do |value|
      assert_not EthereumAddress.valid?(value), value.inspect
    end
  end

  test "refuses something shaped like a private key" do
    error = assert_raises(EthereumAddress::InvalidAddress) { EthereumAddress.parse("0x#{"ab" * 32}") }

    assert_match(/private key/, error.message)
    assert_not EthereumAddress.valid?("cd" * 32)
  end
end
