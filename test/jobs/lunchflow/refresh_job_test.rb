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

  test "enqueues import jobs for linked accounts after refresh" do
    linked_lf_account = lunchflow_accounts(:linked_one)

    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [
        { "id" => 101, "name" => "Test Bank Checking", "institution_name" => "Test Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" }
      ]
    end

    def mock_client.balance(account_id)
      { "amount" => 2500.0, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    LunchflowClient.stub :new, mock_client do
      assert_enqueued_with(job: Lunchflow::ImportTransactionsJob, args: [ { lunchflow_account_id: linked_lf_account.id } ]) do
        Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
      end
    end
  end

  test "does not enqueue import jobs for unlinked accounts after refresh" do
    Account.where(sourceable_type: "Lunchflow::Account").update_all(sourceable_id: nil, sourceable_type: nil)

    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [
        { "id" => 102, "name" => "Test Bank Savings", "institution_name" => "Test Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" }
      ]
    end

    def mock_client.balance(account_id)
      { "amount" => 10000.0, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    LunchflowClient.stub :new, mock_client do
      assert_no_enqueued_jobs(only: Lunchflow::ImportTransactionsJob) do
        Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
      end
    end
  end

  test "sets last_seen_at on accounts that appear in the response" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [ { "id" => 501, "name" => "Seen", "institution_name" => "Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" } ]
    end

    def mock_client.balance(account_id)
      { "amount" => 1.0, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    travel_to Time.zone.local(2026, 4, 27, 12, 0, 0) do
      LunchflowClient.stub :new, mock_client do
        Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
      end

      seen_account = Lunchflow::Account.find_by(remote_id: 501)
      assert_equal Time.current, seen_account.last_seen_at
    end
  end

  test "does not bump last_seen_at on accounts absent from the response" do
    stale_account = Lunchflow::Account.create!(
      connection: @lunchflow_connection,
      remote_id: 502,
      last_seen_at: 3.days.ago
    )
    original_last_seen = stale_account.last_seen_at

    mock_client = Minitest::Mock.new

    def mock_client.accounts
      []
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
    end

    stale_account.reload
    assert_in_delta original_last_seen, stale_account.last_seen_at, 1.second
  end

  test "uses the same timestamp for account last_seen_at and connection refreshed_at" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts
      [ { "id" => 503, "name" => "Sync", "institution_name" => "Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" } ]
    end

    def mock_client.balance(account_id)
      { "amount" => 1.0, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
    end

    @lunchflow_connection.reload
    synced_account = Lunchflow::Account.find_by(remote_id: 503)
    assert_equal @lunchflow_connection.refreshed_at, synced_account.last_seen_at
  end

  test "bumps last_seen_at even when per-account balance fetch fails" do
    existing_account = lunchflow_accounts(:linked_one)
    existing_account.update!(last_seen_at: 3.days.ago)
    original_last_seen = existing_account.last_seen_at

    mock_client = Object.new

    def mock_client.accounts
      [ { "id" => 101, "name" => "Test Bank Checking", "institution_name" => "Test Bank", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" } ]
    end

    def mock_client.balance(account_id)
      raise LunchflowClient::Error, "Balance fetch failed"
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
    end

    existing_account.reload
    assert existing_account.last_seen_at > original_last_seen,
      "expected last_seen_at to be bumped despite balance failure"
    assert_equal @lunchflow_connection.reload.refreshed_at, existing_account.last_seen_at
  end

  test "continues to next account when one account fails" do
    mock_client = Object.new

    def mock_client.accounts
      [
        { "id" => 401, "name" => "Failing Account", "institution_name" => "Bank A", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" },
        { "id" => 402, "name" => "Working Account", "institution_name" => "Bank B", "provider" => "finicity", "currency" => "USD", "status" => "ACTIVE" }
      ]
    end

    def mock_client.balance(account_id)
      raise LunchflowClient::Error, "Balance fetch failed" if account_id == 401
      { "amount" => 500.0, "currency" => "USD" }
    end

    def mock_client.transactions(account_id, include_pending: false)
      []
    end

    LunchflowClient.stub :new, mock_client do
      Lunchflow::RefreshJob.perform_now(@lunchflow_connection.id)
    end

    # The working account was saved despite the first one failing
    assert Lunchflow::Account.exists?(remote_id: 402)

    # Connection still updated successfully
    @lunchflow_connection.reload
    assert_nil @lunchflow_connection.error
    assert_not_nil @lunchflow_connection.refreshed_at
  end
end
