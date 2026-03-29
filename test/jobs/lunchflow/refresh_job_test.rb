require "test_helper"

class Lunchflow::RefreshJobTest < ActiveJob::TestCase
  setup do
    @lunchflow_connection = lunchflow_connections(:one)
  end

  test "refreshes specific connection when ID provided" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [
        {
          "id" => 201,
          "name" => "New Checking",
          "institution_name" => "Chase",
          "institution_logo" => nil,
          "provider" => "finicity",
          "currency" => "USD",
          "status" => "ACTIVE"
        }
      ]
    end

    def mock_client.balance(account_id)
      { "amount" => 1234.56, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      [
        {
          "id" => "txn_new_1",
          "accountId" => 201,
          "amount" => -45.99,
          "currency" => "USD",
          "date" => "2026-01-15",
          "description" => "Grocery Store",
          "merchant" => "Whole Foods",
          "isPending" => false
        }
      ]
    end

    LunchflowClient.stub :new, mock_client do
      assert_difference "Lunchflow::Account.count", 1 do
        assert_difference "Lunchflow::Transaction.count", 1 do
          Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
        end
      end
    end

    @lunchflow_connection.reload
    assert_not_nil @lunchflow_connection.refreshed_at

    lf_account = Lunchflow::Account.find_by(remote_id: 201)
    assert_equal "New Checking", lf_account.name
    assert_equal "Chase", lf_account.institution_name
    assert_equal "1234.56", lf_account.balance

    lf_txn = Lunchflow::Transaction.find_by(remote_id: "txn_new_1")
    assert_equal "-45.99", lf_txn.amount
    assert_equal "Whole Foods", lf_txn.merchant
    assert_equal "Grocery Store", lf_txn.description
  end

  test "skips pending transactions with nil ID" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [ { "id" => 301, "name" => "Test", "institution_name" => "Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" } ]
    end

    def mock_client.balance(account_id)
      { "amount" => 100.0 }
    end

    def mock_client.transactions(account_id, include_pending: false)
      [ { "id" => nil, "amount" => -10.0, "currency" => "USD", "date" => "2026-01-20", "description" => "Pending", "isPending" => true } ]
    end

    LunchflowClient.stub :new, mock_client do
      assert_no_difference "Lunchflow::Transaction.count" do
        Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
      end
    end
  end

  test "updates existing accounts and transactions" do
    existing_account = lunchflow_accounts(:linked_one)
    existing_transaction = lunchflow_transactions(:transaction_one)

    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [ { "id" => 101, "name" => "Updated Name", "institution_name" => "Test Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" } ]
    end

    def mock_client.balance(account_id)
      { "amount" => 9999.99 }
    end

    def mock_client.transactions(account_id, include_pending: false)
      [ { "id" => "lf_txn_1", "amount" => -100.0, "currency" => "USD", "date" => "2026-01-15", "description" => "Updated", "merchant" => "New Merchant", "isPending" => false } ]
    end

    LunchflowClient.stub :new, mock_client do
      assert_no_difference "Lunchflow::Account.count" do
        assert_no_difference "Lunchflow::Transaction.count" do
          Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
        end
      end
    end

    existing_account.reload
    assert_equal "Updated Name", existing_account.name
    assert_equal "9999.99", existing_account.balance

    existing_transaction.reload
    assert_equal "-100.0", existing_transaction.amount
    assert_equal "New Merchant", existing_transaction.merchant
  end

  test "refreshes stale connections when no ID provided" do
    @lunchflow_connection.update!(refreshed_at: 2.days.ago)

    mock_client = Minitest::Mock.new

    def mock_client.accounts
      []
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now
    end

    @lunchflow_connection.reload
    assert @lunchflow_connection.refreshed_at > 1.minute.ago
  end

  test "stores error and continues when API call fails" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts
      raise LunchflowClient::UnauthorizedError, "Active subscription required."
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
    end

    @lunchflow_connection.reload
    assert_equal "Active subscription required.", @lunchflow_connection.error
    assert_not_nil @lunchflow_connection.refreshed_at
  end
end
