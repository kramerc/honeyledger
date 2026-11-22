require "test_helper"

class EsploraClientTest < ActiveSupport::TestCase
  ADDRESS = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4".freeze

  setup do
    @sleeps = []
    @client = EsploraClient.new(base_url: "https://esplora.example/api/", min_interval: 0, sleeper: ->(seconds) { @sleeps << seconds })
  end

  test "address_stats sums confirmed and mempool activity" do
    body = {
      "chain_stats" => { "tx_count" => 2, "funded_txo_sum" => 150_000, "spent_txo_sum" => 50_000 },
      "mempool_stats" => { "tx_count" => 1 }
    }
    called_with = nil

    EsploraClient.stub :get, ->(url, **_options) { called_with = url; response(body) } do
      assert_equal({ tx_count: 3, funded: 150_000, spent: 50_000 }, @client.address_stats(ADDRESS))
    end
    assert_equal "https://esplora.example/api/address/#{ADDRESS}", called_with
  end

  test "address_transactions pages through confirmed history and normalizes it" do
    full_page = (1..EsploraClient::CHAIN_PAGE_SIZE).map { |index| raw_transaction(format("%02d", index)) }
    last_page = [ raw_transaction("zz") ]
    pages = {
      "https://esplora.example/api/address/#{ADDRESS}/txs/chain" => full_page,
      "https://esplora.example/api/address/#{ADDRESS}/txs/chain/25" => last_page
    }

    transactions = EsploraClient.stub :get, ->(url, **_options) { response(pages.fetch(url)) } do
      @client.address_transactions(ADDRESS)
    end

    # A short page is the last: no request is made for a page after "zz".
    assert_equal 26, transactions.size
    assert_equal "zz", transactions.last[:txid]
    first = transactions.first
    assert_equal 1_000, first[:fee]
    assert_equal 800_000, first[:block_height]
    assert_equal Time.zone.at(1_700_000_000), first[:block_time]
    assert first[:confirmed]
    assert_equal [ { address: "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", value: 10_000 } ], first[:inputs]
    assert_equal "01", first[:txid]
    assert_equal [ { address: ADDRESS, value: 9_000 } ], first[:outputs]
  end

  test "a coinbase input without a prevout normalizes to a nil address" do
    raw = raw_transaction("aa").merge("vin" => [ { "is_coinbase" => true } ])

    transactions = EsploraClient.stub :get, ->(url, **_options) { response(url.end_with?("/chain") ? [ raw ] : []) } do
      @client.address_transactions(ADDRESS)
    end

    assert_equal [ { address: nil, value: 0 } ], transactions.first[:inputs]
  end

  test "a 429 is retried with backoff and then succeeds" do
    responses = [ response("Too Many Requests", code: 429), response("Too Many Requests", code: 429, headers: { "retry-after" => "7" }),
                  response({ "chain_stats" => { "tx_count" => 1 } }) ]

    stats = EsploraClient.stub :get, ->(*_args, **_options) { responses.shift } do
      @client.address_stats(ADDRESS)
    end

    assert_equal 1, stats[:tx_count]
    assert_equal [ 2, 7 ], @sleeps, "exponential backoff, then the server's Retry-After"
  end

  test "persistent 429s raise RateLimitedError after the retries" do
    calls = 0

    EsploraClient.stub :get, ->(*_args, **_options) { calls += 1; response("Too Many Requests", code: 429) } do
      assert_raises(EsploraClient::RateLimitedError) { @client.address_stats(ADDRESS) }
    end
    assert_equal EsploraClient::MAX_RETRIES + 1, calls
    assert_equal [ 2, 4, 8, 16 ], @sleeps
  end

  test "requests are paced by the minimum interval" do
    client = EsploraClient.new(base_url: "https://esplora.example/api", min_interval: 60, sleeper: ->(seconds) { @sleeps << seconds })

    EsploraClient.stub :get, ->(*_args, **_options) { response({ "chain_stats" => {} }) } do
      client.address_stats(ADDRESS)
      client.address_stats(ADDRESS)
    end

    assert_equal 1, @sleeps.size, "only the second request waits"
    assert_in_delta 60, @sleeps.first, 1
  end

  test "other failures raise Error without echoing the response body" do
    EsploraClient.stub :get, ->(*_args, **_options) { response("internal secret detail", code: 400) } do
      error = assert_raises(EsploraClient::Error) { @client.address_stats(ADDRESS) }
      assert_equal "The explorer returned HTTP 400", error.message
    end
  end

  test "a 200 that is not JSON raises Error" do
    EsploraClient.stub :get, ->(*_args, **_options) { response("<!doctype html><title>mempool</title>") } do
      error = assert_raises(EsploraClient::Error) { @client.address_stats(ADDRESS) }
      assert_match(/did not return JSON/, error.message)
    end
  end

  test "a transaction list of non-objects raises Error" do
    EsploraClient.stub :get, ->(*_args, **_options) { response([ "aa" ]) } do
      assert_raises(EsploraClient::Error) { @client.address_transactions(ADDRESS) }
    end
  end

  test "TLS and parse failures raise Error" do
    [ OpenSSL::SSL::SSLError, Errno::ECONNRESET, JSON::ParserError ].each do |error_class|
      EsploraClient.stub :get, ->(*_args, **_options) { raise error_class } do
        assert_raises(EsploraClient::Error, error_class.name) { @client.address_stats(ADDRESS) }
      end
    end
  end

  test "network failures raise Error" do
    EsploraClient.stub :get, ->(*_args, **_options) { raise SocketError, "getaddrinfo failed" } do
      error = assert_raises(EsploraClient::Error) { @client.address_stats(ADDRESS) }
      assert_match(/Could not reach/, error.message)
    end
  end

  private

    def response(parsed, code: 200, headers: {})
      Struct.new(:code, :parsed_response, :body, :headers).new(code, parsed, parsed.is_a?(String) ? parsed : parsed.to_json, headers)
    end

    def raw_transaction(txid)
      {
        "txid" => txid,
        "fee" => 1_000,
        "status" => { "confirmed" => true, "block_height" => 800_000, "block_time" => 1_700_000_000 },
        "vin" => [ { "prevout" => { "scriptpubkey_address" => "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", "value" => 10_000 } } ],
        "vout" => [ { "scriptpubkey_address" => ADDRESS, "value" => 9_000 } ]
      }
    end
end
