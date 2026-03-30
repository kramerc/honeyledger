require "test_helper"

class LunchflowClientTest < ActiveSupport::TestCase
  test "accounts fetches with api key header" do
    client = LunchflowClient.new(api_key: "test_key")

    called_with = nil
    response = { "accounts" => [], "total" => 0 }
    stub_get = ->(*args) { called_with = args; response }

    # Stub code to return 200
    response.define_singleton_method(:code) { 200 }

    LunchflowClient.stub :get, stub_get do
      result = client.accounts
      assert_equal [], result
      assert_equal "/accounts", called_with[0]
      assert_equal "test_key", called_with[1][:headers]["x-api-key"]
    end
  end

  test "transactions fetches for specific account" do
    client = LunchflowClient.new(api_key: "test_key")

    called_with = nil
    response = { "transactions" => [ { "id" => "txn_1" } ], "total" => 1 }
    stub_get = ->(*args) { called_with = args; response }

    response.define_singleton_method(:code) { 200 }

    LunchflowClient.stub :get, stub_get do
      result = client.transactions(42, include_pending: true)
      assert_equal [ { "id" => "txn_1" } ], result
      assert_equal "/accounts/42/transactions", called_with[0]
      assert_equal true, called_with[1][:query][:include_pending]
    end
  end

  test "balance fetches for specific account" do
    client = LunchflowClient.new(api_key: "test_key")

    called_with = nil
    response = { "balance" => { "amount" => 1234.56, "currency" => "USD" } }
    stub_get = ->(*args) { called_with = args; response }

    response.define_singleton_method(:code) { 200 }

    LunchflowClient.stub :get, stub_get do
      result = client.balance(42)
      assert_equal({ "amount" => 1234.56, "currency" => "USD" }, result)
      assert_equal "/accounts/42/balance", called_with[0]
    end
  end

  test "raises UnauthorizedError on 401" do
    client = LunchflowClient.new(api_key: "bad_key")

    response = { "error" => "Unauthorized", "message" => "Invalid API key" }
    response.define_singleton_method(:code) { 401 }

    LunchflowClient.stub :get, response do
      error = assert_raises(LunchflowClient::UnauthorizedError) { client.accounts }
      assert_equal "Invalid API key", error.message
    end
  end

  test "raises UnauthorizedError on 403" do
    client = LunchflowClient.new(api_key: "expired_key")

    response = { "error" => "Forbidden", "message" => "Active subscription required. Please subscribe to use the API." }
    response.define_singleton_method(:code) { 403 }

    LunchflowClient.stub :get, response do
      error = assert_raises(LunchflowClient::UnauthorizedError) { client.accounts }
      assert_equal "Active subscription required. Please subscribe to use the API.", error.message
    end
  end

  test "raises Error on other error status codes" do
    client = LunchflowClient.new(api_key: "test_key")

    response = { "error" => "Internal Server Error", "message" => "Something went wrong" }
    response.define_singleton_method(:code) { 500 }

    LunchflowClient.stub :get, response do
      error = assert_raises(LunchflowClient::Error) { client.accounts }
      assert_equal "Something went wrong", error.message
    end
  end
end
