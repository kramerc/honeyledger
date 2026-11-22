require "test_helper"

class Blockchain::ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ZPUB = "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs".freeze

  test "fills in a default label" do
    connection = Blockchain::Connection.create!(user: users(:two), chain: "bitcoin", identifier: ZPUB)

    assert_equal "Bitcoin wallet", connection.name
  end

  test "lowercases a bech32 address so it matches what explorers report" do
    connection = Blockchain::Connection.create!(user: users(:one), chain: "bitcoin", identifier: "BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4")

    assert_equal "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", connection.identifier
    duplicate = Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    assert_not duplicate.valid?, "an address differing only in case is the same wallet"
  end

  test "keeps the case of Base58 identifiers" do
    assert_equal ZPUB, Blockchain::Connection.new(identifier: " #{ZPUB} ").identifier
  end

  test "accepts a mainnet address and strips whitespace" do
    connection = Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: "  bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 \n")

    assert connection.valid?, connection.errors.full_messages.to_sentence
    assert_equal "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", connection.identifier
    assert_not connection.extended_key?
    assert_nil connection.extended_key
  end

  test "rejects testnet keys and addresses" do
    upub = "upub5EFU65HtV5TeiSHmZZm7FUffBGy8UKeqp7vw43jYbvZPpoVsgU93oac7Wk3u6moKegAEWtGNF8DehrnHtv21XXEMYRUocHqguyjknFHYfgY"
    testnet_address = "tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c"

    assert_includes Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: upub).tap(&:validate).errors[:identifier], "must be a mainnet key"
    assert_includes Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: testnet_address).tap(&:validate).errors[:identifier], "must be a mainnet address"
  end

  test "rejects garbage and private keys" do
    garbage = Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: "not a wallet")
    private_key = Blockchain::Connection.new(user: users(:one), chain: "bitcoin",
      identifier: "zprvAdG4iTXWBoARxkkzNpNh8r6Qag3irQB8PzEMkAFeTRXxHpbF9z4QgEvBRmfvqWvGp42t42nvgGpNgYSJA9iefm1yYNZKEm7z6qUWCroSQnE")

    assert_not garbage.valid?
    assert_match(/not a valid Bitcoin address/, garbage.errors[:identifier].first)
    assert_not private_key.valid?
    assert_match(/private key/, private_key.errors[:identifier].first)
  end

  test "rejects a wallet the user already tracks" do
    duplicate = Blockchain::Connection.new(user: users(:one), chain: "bitcoin", identifier: blockchain_connections(:xpub_wallet).identifier)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:identifier], "is already tracked"
  end

  test "rejects an unknown chain" do
    connection = Blockchain::Connection.new(user: users(:one), chain: "dogecoin", identifier: ZPUB)

    assert_not connection.valid?
    assert connection.errors[:chain].any?
  end

  test "refresh enqueues a refresh job" do
    connection = blockchain_connections(:xpub_wallet)

    assert_enqueued_with(job: Blockchain::RefreshJob, args: [ connection.id ]) { connection.refresh }
  end

  test "client queries the operator-configured explorer" do
    original = Rails.configuration.x.esplora_url
    Rails.configuration.x.esplora_url = "https://esplora.internal.example/api"

    client = blockchain_connections(:xpub_wallet).client

    assert_equal "https://esplora.internal.example/api", client.instance_variable_get(:@base_url)
  ensure
    Rails.configuration.x.esplora_url = original
  end

  ETHEREUM_ADDRESS = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359".freeze

  test "accepts a checksummed Ethereum address, stores it lowercase, and names the wallet" do
    with_evm_explorer do
      connection = Blockchain::Connection.create!(user: users(:one), chain: "ethereum", identifier: " #{ETHEREUM_ADDRESS} ")

      assert_equal ETHEREUM_ADDRESS.downcase, connection.identifier
      assert_equal "Ethereum wallet", connection.name
      assert_not connection.extended_key?
      assert connection.reload.valid?, "a stored lowercase address stays valid"
    end
  end

  test "rejects an Ethereum address with a broken checksum, a private key, or garbage" do
    with_evm_explorer do
      typo = Blockchain::Connection.new(user: users(:one), chain: "ethereum", identifier: ETHEREUM_ADDRESS.sub("bB79", "bb79"))
      private_key = Blockchain::Connection.new(user: users(:one), chain: "ethereum", identifier: "0x#{"ab" * 32}")
      garbage = Blockchain::Connection.new(user: users(:one), chain: "ethereum", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")

      assert_match(/checksum/, typo.tap(&:validate).errors[:identifier].first)
      assert_match(/private key/, private_key.tap(&:validate).errors[:identifier].first)
      assert_match(/not a valid Ethereum address/, garbage.tap(&:validate).errors[:identifier].first)
    end
  end

  test "an Ethereum address differing only in case is the same wallet" do
    with_evm_explorer do
      duplicate = Blockchain::Connection.new(user: users(:two), chain: "ethereum", identifier: blockchain_connections(:eth_wallet).identifier.upcase.sub("0X", "0x"))

      assert_includes duplicate.tap(&:validate).errors[:identifier], "is already tracked"
    end
  end

  test "Ethereum wallets need an operator API key" do
    with_evm_explorer(api_key: nil) do
      connection = Blockchain::Connection.new(user: users(:one), chain: "ethereum", identifier: ETHEREUM_ADDRESS)

      assert_not connection.valid?
      assert_match(/Ethereum wallets are not configured/, connection.errors[:base].first)
      assert_equal [ "bitcoin" ], Blockchain::Connection.available_chains
      assert blockchain_connections(:eth_wallet).valid?, "existing wallets stay valid if the key is removed"
    end

    with_evm_explorer { assert_equal %w[bitcoin ethereum], Blockchain::Connection.available_chains }
    with_evm_explorer(provider: "Etherscan") do
      assert_not Blockchain::Connection.chain_available?(:ethereum), "a mistyped EVM_EXPLORER does not offer Ethereum"
    end
    assert_not Blockchain::Connection.chain_available?("dogecoin")
  end

  test "an Ethereum wallet's client is the configured EVM explorer" do
    with_evm_explorer(provider: "etherscan") do
      client = blockchain_connections(:eth_wallet).client

      assert_kind_of EvmExplorerClient, client
      assert_equal "https://api.etherscan.io/v2/api", client.instance_variable_get(:@base_url)
      assert_equal EvmExplorerTestHelper::TEST_API_KEY, client.instance_variable_get(:@api_key)
    end
  end

  test "display_identifier shortens long identifiers" do
    assert_equal "zpub6rFR7y…GutZYs", blockchain_connections(:xpub_wallet).display_identifier
    assert_equal "short", Blockchain::Connection.new(identifier: "short").display_identifier
  end
end
