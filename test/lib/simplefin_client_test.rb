require "test_helper"

class SimplefinClientTest < ActiveSupport::TestCase
  test "initialize with url parses credentials" do
    client = SimplefinClient.new(url: "https://user:pass@beta-bridge.simplefin.org/simplefin")
    assert_instance_of SimplefinClient, client
  end

  test "initialize with username and password" do
    client = SimplefinClient.new(username: "user", password: "pass")
    assert_instance_of SimplefinClient, client
  end

  test "info calls get" do
    client = SimplefinClient.new
    expected = { "versions" => [ "1.0" ] }

    SimplefinClient.stub :get, expected do
      result = client.info
      assert_equal expected, result
    end
  end

  test "claim posts to decoded token URL" do
    client = SimplefinClient.new
    token = Base64.encode64("https://example.com/claim/token123")

    SimplefinClient.stub :post, "https://user:pass@example.com/simplefin" do
      result = client.claim(token)
      assert_equal "https://user:pass@example.com/simplefin", result
    end
  end

  test "accounts raises UnauthorizedError without credentials" do
    client = SimplefinClient.new
    assert_raises(SimplefinClient::UnauthorizedError) { client.accounts }
  end

  test "accounts fetches with auth" do
    client = SimplefinClient.new(username: "user", password: "pass")

    SimplefinClient.stub :get, { "accounts" => [] } do
      result = client.accounts(start_date: 1000, pending: true, balances_only: true)
      assert_equal({ "accounts" => [] }, result)
    end
  end
end
