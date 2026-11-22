require "test_helper"

class EvmExplorerClientTest < ActiveSupport::TestCase
  # EIP-55 example addresses and placeholder hashes, never real wallets.
  WALLET = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed".freeze
  OTHER = "0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359".freeze
  API_KEY = "proapi_secretkey123".freeze
  # Paging tests use a small page so they stay fast.
  PAGE_SIZE = 10

  setup do
    @sleeps = []
    @client = build_client
  end

  test "the Blockscout preset sends chain_id and the key to its base URL" do
    calls = []

    EvmExplorerClient.stub :get, ->(url, query:, **_options) { calls << [ url, query ]; response(envelope([])) } do
      @client.normal_transactions(WALLET)
    end

    url, query = calls.sole
    assert_equal "https://api.blockscout.com/v2/api", url
    assert_equal 1, query["chain_id"]
    assert_equal API_KEY, query[:apikey]
    assert_equal({ module: "account", action: "txlist", address: WALLET, startblock: 0, sort: "asc", page: 1, offset: 5_000 },
      query.slice(:module, :action, :address, :startblock, :sort, :page, :offset))
  end

  test "the Etherscan preset sends chainid, and a base URL override wins" do
    client = build_client(provider: "etherscan", base_url: "https://explorer.example/api/")
    calls = []

    EvmExplorerClient.stub :get, ->(url, query:, **_options) { calls << [ url, query ]; response({ "jsonrpc" => "2.0", "id" => 1, "result" => "0x10" }) } do
      assert_equal 16, client.block_number
    end

    url, query = calls.sole
    assert_equal "https://explorer.example/api", url
    assert_equal 1, query["chainid"]
    assert_equal [ "proxy", "eth_blockNumber" ], query.values_at(:module, :action)
  end

  test "Blockscout's chain tip route" do
    calls = []

    EvmExplorerClient.stub :get, ->(_url, query:, **_options) { calls << query; response({ "jsonrpc" => "2.0", "id" => 1, "result" => "0x193f043" }) } do
      assert_equal 0x193f043, @client.block_number
    end
    assert_equal [ "block", "eth_block_number" ], calls.sole.values_at(:module, :action)
  end

  test "balance reads the address's wei balance" do
    calls = []

    balance = EvmExplorerClient.stub :get, ->(_url, query:, **_options) { calls << query; response(envelope("4311373694308678363")) } do
      @client.balance(WALLET)
    end

    assert_equal 4_311_373_694_308_678_363, balance
    assert_equal [ "account", "balance", WALLET ], calls.sole.values_at(:module, :action, :address)
    [ envelope("1.5"), envelope(nil), { "status" => "0", "message" => "NOTOK", "result" => "Error! Invalid address format" } ].each do |body|
      assert_raises(EvmExplorerClient::Error, body.inspect) { stub_responses(body) { @client.balance(WALLET) } }
    end
  end

  test "an unknown provider is an Error" do
    error = assert_raises(EvmExplorerClient::Error) { build_client(provider: "nope") }

    assert_match(/EVM_EXPLORER/, error.message)
  end

  test "normalizes normal transactions in wei with the gas fee" do
    raw = normal("0x#{"a" * 64}", from: OTHER.upcase.sub("0X", "0x"), to: WALLET, value: "1500000000000000000", block: "100")

    transactions = stub_responses(envelope([ raw ])) { @client.normal_transactions(WALLET) }

    assert_equal [ {
      hash: "0x#{"a" * 64}", from: OTHER, to: WALLET, value: 1_500_000_000_000_000_000, fee: 21_000 * 30_000_000_000,
      failed: false, block_number: 100, timestamp: Time.zone.at(1_700_000_000), contract_address: nil
    } ], transactions
  end

  test "a reverted transaction is marked failed" do
    raw = normal("0x#{"b" * 64}", from: WALLET, to: OTHER, value: "5").merge("isError" => "1")

    assert stub_responses(envelope([ raw ])) { @client.normal_transactions(WALLET) }.sole[:failed]
  end

  test "normalizes both providers' internal transaction shapes" do
    etherscan = { "hash" => "0x#{"c" * 64}", "traceId" => "0_1", "from" => OTHER, "to" => WALLET, "value" => "7",
                  "isError" => "0", "blockNumber" => "5", "timeStamp" => "1700000000", "contractAddress" => "" }
    blockscout = { "transactionHash" => "0x#{"d" * 64}", "index" => "2", "from" => OTHER, "to" => "", "contractAddress" => WALLET,
                   "value" => "9", "isError" => "0", "blockNumber" => "6", "timeStamp" => "1700000100", "type" => "create" }

    transactions = stub_responses(envelope([ etherscan, blockscout ])) { @client.internal_transactions(WALLET) }

    assert_equal [ [ "0x#{"c" * 64}", "0_1", WALLET, 7 ], [ "0x#{"d" * 64}", "2", WALLET, 9 ] ],
      transactions.map { |entry| entry.values_at(:hash, :trace_id, :to, :value) }
  end

  test "Blockscout's partially indexed status still returns its results" do
    raw = { "transactionHash" => "0x#{"e" * 64}", "index" => "0", "from" => OTHER, "to" => WALLET, "value" => "1",
            "isError" => "0", "blockNumber" => "1", "timeStamp" => "1700000000" }
    body = { "status" => "2", "message" => "Some internal transactions within this block range have not yet been processed", "result" => [ raw ] }

    assert_equal 1, stub_responses(body) { @client.internal_transactions(WALLET) }.size
  end

  test "no transactions is an empty list" do
    body = { "status" => "0", "message" => "No transactions found", "result" => [] }

    assert_equal [], stub_responses(body) { @client.normal_transactions(WALLET) }
  end

  test "pages by block range past a full page and drops the repeated block" do
    page_size = PAGE_SIZE
    client = build_client(page_size: page_size)
    first_page = (1..page_size).map { |index| normal(format("0x%064x", index), from: OTHER, to: WALLET, value: "1", block: (index / 2 + 1).to_s) }
    last_block = first_page.last["blockNumber"]
    # The second request restarts at the last block, so it repeats that block's transactions.
    second_page = first_page.select { |raw| raw["blockNumber"] == last_block } + [ normal(format("0x%064x", page_size + 1), from: OTHER, to: WALLET, value: "1", block: (last_block.to_i + 1).to_s) ]
    start_blocks = []

    transactions = EvmExplorerClient.stub :get, ->(_url, query:, **_options) {
      start_blocks << query[:startblock]
      response(envelope(query[:startblock].zero? ? first_page : second_page))
    } do
      client.normal_transactions(WALLET)
    end

    assert_equal [ 0, last_block.to_i ], start_blocks
    assert_equal page_size + 1, transactions.size
    assert_equal transactions.map { |entry| entry[:hash] }.uniq, transactions.map { |entry| entry[:hash] }
  end

  test "a full page from a single block raises instead of looping" do
    page = (1..PAGE_SIZE).map { |index| normal(format("0x%064x", index), from: OTHER, to: WALLET, value: "1", block: "0") }

    client = build_client(page_size: PAGE_SIZE)

    error = assert_raises(EvmExplorerClient::Error) { stub_responses(envelope(page)) { client.normal_transactions(WALLET) } }
    assert_match(/single block/, error.message)
  end

  test "each preset pages at its own size" do
    offsets = []
    capture = ->(_url, query:, **_options) { offsets << query[:offset]; response(envelope([])) }

    EvmExplorerClient.stub :get, capture do
      build_client(provider: "blockscout").normal_transactions(WALLET)
      build_client(provider: "etherscan").normal_transactions(WALLET)
    end

    assert_equal [ 5_000, 1_000 ], offsets
    assert EvmExplorerClient.known_provider?(:etherscan)
    assert_not EvmExplorerClient.known_provider?("Etherscan")
  end

  test "a transaction without a block number or timestamp is an Error, not block 0" do
    valid = normal("0x#{"9" * 64}", from: OTHER, to: WALLET, value: "1")

    [ { "blockNumber" => "" }, { "timeStamp" => nil } ].each do |change|
      error = assert_raises(EvmExplorerClient::Error) { stub_responses(envelope([ valid.merge(change) ])) { @client.normal_transactions(WALLET) } }
      assert_match(/without a (block number|timestamp)/, error.message)
    end
  end

  test "a malformed status line is recorded as an Error" do
    EvmExplorerClient.stub :get, ->(*_args, **_options) { raise Net::HTTPBadResponse, "wrong status line" } do
      assert_match(/Could not reach/, assert_raises(EvmExplorerClient::Error) { @client.block_number }.message)
    end
  end

  test "a rate limit inside a 200 body is retried with backoff" do
    responses = [ response({ "status" => "0", "message" => "NOTOK", "result" => "Max rate limit reached" }), response(envelope([])) ]

    EvmExplorerClient.stub :get, ->(*_args, **_options) { responses.shift } do
      assert_equal [], @client.normal_transactions(WALLET)
    end
    assert_equal [ 2 ], @sleeps
  end

  test "an HTTP 429 is retried, honouring Retry-After" do
    responses = [ response("slow down", code: 429, headers: { "retry-after" => "5" }), response(envelope([])) ]

    EvmExplorerClient.stub :get, ->(*_args, **_options) { responses.shift } do
      @client.normal_transactions(WALLET)
    end
    assert_equal [ 5 ], @sleeps
  end

  test "a rejected key never puts the key in the message" do
    [
      response({ "error" => "Proceed with API key or make a X402 payment to continue" }, code: 402),
      response({ "status" => "0", "message" => "NOTOK", "result" => "Invalid API Key #{API_KEY}" })
    ].each do |rejection|
      error = EvmExplorerClient.stub :get, ->(*_args, **_options) { rejection } do
        assert_raises(EvmExplorerClient::Error) { @client.normal_transactions(WALLET) }
      end
      assert_match(/API key/, error.message)
      assert_no_match(/#{API_KEY}/, error.message)
    end
  end

  test "another refusal shows the provider's message with the key scrubbed" do
    body = { "status" => "0", "message" => "Invalid address format #{API_KEY}", "result" => nil }

    error = assert_raises(EvmExplorerClient::Error) { stub_responses(body) { @client.normal_transactions(WALLET) } }
    assert_equal "The explorer refused the request (Invalid address format [FILTERED])", error.message
  end

  test "Blockscout's empty internal list is an empty history" do
    body = { "status" => "0", "message" => "No internal transactions found", "result" => [] }

    assert_equal [], stub_responses(body) { @client.internal_transactions(WALLET) }
  end

  test "any other failure with an empty list is an Error, not an empty wallet" do
    body = { "status" => "0", "message" => "Query timeout", "result" => [] }

    error = assert_raises(EvmExplorerClient::Error) { stub_responses(body) { @client.normal_transactions(WALLET) } }
    assert_equal "The explorer refused the request (Query timeout)", error.message
  end

  test "a failure status with a non-empty list is still a refusal" do
    body = { "status" => "0", "message" => "Query timeout", "result" => [ { "unexpected" => true } ] }

    error = assert_raises(EvmExplorerClient::Error) { stub_responses(body) { @client.normal_transactions(WALLET) } }
    assert_equal "The explorer refused the request (Query timeout)", error.message
  end

  test "a missing key fails before any request" do
    client = build_client(api_key: "")

    EvmExplorerClient.stub :get, ->(*_args, **_options) { flunk "no request without a key" } do
      error = assert_raises(EvmExplorerClient::Error) { client.normal_transactions(WALLET) }
      assert_match(/EVM_EXPLORER_API_KEY/, error.message)
    end
  end

  test "other HTTP failures and transport errors raise Error" do
    EvmExplorerClient.stub :get, ->(*_args, **_options) { response("boom", code: 500) } do
      assert_equal "The explorer returned HTTP 500", assert_raises(EvmExplorerClient::Error) { @client.block_number }.message
    end

    [ SocketError, Net::ReadTimeout, JSON::ParserError ].each do |error_class|
      EvmExplorerClient.stub :get, ->(*_args, **_options) { raise error_class } do
        assert_match(/Could not reach/, assert_raises(EvmExplorerClient::Error) { @client.block_number }.message)
      end
    end
  end

  test "malformed responses raise Error" do
    valid = normal("0x#{"f" * 64}", from: OTHER, to: WALLET, value: "1")
    bodies = [
      "<!doctype html>",
      { "message" => "OK" },
      envelope("not a list"),
      envelope([ "not an object" ]),
      envelope([ valid.merge("hash" => "0x123") ]),
      envelope([ valid.merge("value" => "1.5") ]),
      envelope([ valid.merge("from" => "nobody") ])
    ]

    bodies.each do |body|
      assert_raises(EvmExplorerClient::Error, body.inspect) { stub_responses(body) { @client.normal_transactions(WALLET) } }
    end
    assert_raises(EvmExplorerClient::Error) { stub_responses({ "jsonrpc" => "2.0", "result" => nil }) { @client.block_number } }
  end

  test "requests are paced by the minimum interval" do
    client = build_client(min_interval: 60)

    EvmExplorerClient.stub :get, ->(*_args, **_options) { response(envelope([])) } do
      client.normal_transactions(WALLET)
      client.internal_transactions(WALLET)
    end

    assert_equal 1, @sleeps.size, "only the second request waits"
    assert_in_delta 60, @sleeps.first, 1
  end

  private

    def build_client(provider: "blockscout", api_key: API_KEY, base_url: nil, page_size: nil, min_interval: 0)
      EvmExplorerClient.new(provider: provider, api_key: api_key, base_url: base_url, chain_id: EvmExplorerClient::ETHEREUM_MAINNET,
        page_size: page_size, min_interval: min_interval, sleeper: ->(seconds) { @sleeps << seconds })
    end

    def stub_responses(body, &block)
      EvmExplorerClient.stub(:get, ->(*_args, **_options) { response(body) }, &block)
    end

    def envelope(result)
      { "status" => "1", "message" => "OK", "result" => result }
    end

    def normal(hash, from:, to:, value:, block: "100")
      {
        "hash" => hash, "from" => from, "to" => to, "value" => value, "gasUsed" => "21000", "gasPrice" => "30000000000",
        "isError" => "0", "txreceipt_status" => "1", "blockNumber" => block, "timeStamp" => "1700000000", "contractAddress" => ""
      }
    end

    def response(parsed, code: 200, headers: {})
      Struct.new(:code, :parsed_response, :body, :headers).new(code, parsed, parsed.is_a?(String) ? parsed : parsed.to_json, headers)
    end
end
