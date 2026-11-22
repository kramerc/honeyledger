require "test_helper"

class Blockchain::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "new renders" do
    get new_blockchain_connection_url

    assert_response :success
  end

  test "create saves the wallet and enqueues a refresh" do
    assert_difference "@user.blockchain_connections.count", 1 do
      assert_enqueued_with(job: Blockchain::RefreshJob) do
        post blockchain_connections_url, params: { blockchain_connection: {
          chain: "bitcoin", name: "Spending", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", api_url: ""
        } }
      end
    end

    assert_redirected_to integrations_url
    assert_equal "https://mempool.space/api", @user.blockchain_connections.find_by(name: "Spending").api_url
  end

  test "create re-renders on an invalid identifier" do
    assert_no_difference "Blockchain::Connection.count" do
      post blockchain_connections_url, params: { blockchain_connection: { chain: "bitcoin", identifier: "nope" } }
    end

    assert_response :unprocessable_entity
  end

  test "create responds to JSON" do
    post blockchain_connections_url(format: :json), params: { blockchain_connection: {
      chain: "bitcoin", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    } }
    assert_response :created

    post blockchain_connections_url(format: :json), params: { blockchain_connection: { chain: "bitcoin", identifier: "nope" } }
    assert_response :unprocessable_entity
  end

  test "refresh enqueues a refresh for the user's wallet" do
    connection = blockchain_connections(:xpub_wallet)

    assert_enqueued_with(job: Blockchain::RefreshJob, args: [ connection.id ]) do
      post refresh_blockchain_connection_url(connection)
    end
    assert_redirected_to integrations_url
  end

  test "destroy removes the wallet" do
    assert_difference "Blockchain::Connection.count", -1 do
      delete blockchain_connection_url(blockchain_connections(:xpub_wallet))
    end

    assert_redirected_to integrations_url
  end

  test "destroy responds to JSON" do
    delete blockchain_connection_url(blockchain_connections(:xpub_wallet), format: :json)

    assert_response :no_content
  end

  test "cannot touch another user's wallet" do
    other = blockchain_connections(:address_wallet)

    post refresh_blockchain_connection_url(other)
    assert_response :not_found

    assert_no_difference "Blockchain::Connection.count" do
      delete blockchain_connection_url(other)
    end
    assert_response :not_found
  end
end
