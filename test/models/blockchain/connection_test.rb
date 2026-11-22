require "test_helper"

class Blockchain::ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ZPUB = "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs".freeze

  test "fills in the default explorer URL and label" do
    connection = Blockchain::Connection.create!(user: users(:two), chain: "bitcoin", identifier: ZPUB)

    assert_equal "https://mempool.space/api", connection.api_url
    assert_equal "Bitcoin wallet", connection.name
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

  test "rejects an unknown chain and a non-http explorer URL" do
    connection = Blockchain::Connection.new(user: users(:one), chain: "dogecoin", identifier: ZPUB, api_url: "ftp://example")

    assert_not connection.valid?
    assert connection.errors[:chain].any?
    assert_includes connection.errors[:api_url], "must be an http(s) URL"
  end

  test "refresh enqueues a refresh job" do
    connection = blockchain_connections(:xpub_wallet)

    assert_enqueued_with(job: Blockchain::RefreshJob, args: [ connection.id ]) { connection.refresh }
  end

  test "client points at the explorer URL" do
    assert_instance_of EsploraClient, blockchain_connections(:xpub_wallet).client
  end

  test "display_identifier shortens long identifiers" do
    assert_equal "zpub6rFR7y…GutZYs", blockchain_connections(:xpub_wallet).display_identifier
    assert_equal "short", Blockchain::Connection.new(identifier: "short").display_identifier
  end
end
