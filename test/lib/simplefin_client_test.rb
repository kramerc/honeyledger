require "test_helper"

class SimplefinClientTest < ActiveSupport::TestCase
  test "initialize with url parses credentials and sets base uri" do
    client = SimplefinClient.new(url: "https://user:pass@beta-bridge.simplefin.org/simplefin")

    called_with = nil
    stub_get = ->(*args) { called_with = args; {} }

    SimplefinClient.stub :get, stub_get do
      client.accounts
      opts = called_with[1]
      assert_equal({ username: "user", password: "pass" }, opts[:basic_auth])
    end
  end

  test "initialize with username and password" do
    client = SimplefinClient.new(username: "user", password: "pass")

    called_with = nil
    stub_get = ->(*args) { called_with = args; {} }

    SimplefinClient.stub :get, stub_get do
      client.accounts
      opts = called_with[1]
      assert_equal({ username: "user", password: "pass" }, opts[:basic_auth])
    end
  end

  test "info calls get on /info" do
    client = SimplefinClient.new

    called_with = nil
    stub_get = ->(*args) { called_with = args; { "versions" => [ "1.0" ] } }

    SimplefinClient.stub :get, stub_get do
      result = client.info
      assert_equal({ "versions" => [ "1.0" ] }, result)
      assert_equal "/info", called_with.first
    end
  end

  test "claim posts to decoded token URL" do
    client = SimplefinClient.new
    claim_url = "https://example.com/claim/token123"
    token = Base64.encode64(claim_url)

    called_with = nil
    stub_post = ->(*args) { called_with = args; "https://user:pass@example.com/simplefin" }

    SimplefinClient.stub :post, stub_post do
      result = client.claim(token)
      assert_equal "https://user:pass@example.com/simplefin", result
      assert_equal claim_url, called_with.first
    end
  end

  test "accounts raises UnauthorizedError without credentials" do
    client = SimplefinClient.new
    assert_raises(SimplefinClient::UnauthorizedError) { client.accounts }
  end

  test "accounts fetches with auth and query params" do
    client = SimplefinClient.new(username: "user", password: "pass")

    called_with = nil
    stub_get = ->(*args) { called_with = args; { "accounts" => [] } }

    SimplefinClient.stub :get, stub_get do
      result = client.accounts(start_date: 1000, pending: true, balances_only: true)
      assert_equal({ "accounts" => [] }, result)
      assert_equal "/accounts", called_with[0]
      opts = called_with[1]
      assert_equal({ username: "user", password: "pass" }, opts[:basic_auth])
      assert_equal 1000, opts[:query][:"start-date"]
      assert_equal 1, opts[:query][:pending]
      assert_equal 1, opts[:query][:"balances-only"]
      assert_equal 2, opts[:query][:version]
    end
  end
end
