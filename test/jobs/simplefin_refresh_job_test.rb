require "test_helper"

class Simplefin::RefreshJobTest < ActiveJob::TestCase
  setup do
    @simplefin_connection = simplefin_connections(:one)
  end

  test "refreshes all stale connections when no ID provided" do
    # Set connection as stale (older than 1 day)
    @simplefin_connection.update!(refreshed_at: 2.days.ago)
    # Make sure other connections are fresh so only one is processed
    Simplefin::Connection.where.not(id: @simplefin_connection.id).update_all(refreshed_at: Time.current)

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [
          {
            "conn_id" => "conn_1",
            "name" => "Test Bank - User",
            "org_id" => "testbank",
            "org_url" => "testbank.com",
            "sfin_url" => "https://sfin.testbank.com"
          }
        ],
        "accounts" => [
          {
            "id" => "acc_123",
            "conn_id" => "conn_1",
            "name" => "Checking",
            "currency" => "USD",
            "balance" => "1000.00",
            "available-balance" => "900.00",
            "balance-date" => Time.current.to_i,
            "transactions" => [],
            "extra" => {}
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_difference "Simplefin::Account.count", 1 do
        Simplefin::RefreshJob.perform_now
      end
    end

    @simplefin_connection.reload
    assert_not_nil @simplefin_connection.refreshed_at
    assert @simplefin_connection.refreshed_at > 1.minute.ago
  end

  test "refreshes specific connection when ID provided" do
    # Set connection as recently refreshed (should still refresh when ID is specified)
    @simplefin_connection.update!(refreshed_at: 1.hour.ago)

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [
          {
            "conn_id" => "conn_2",
            "name" => "Test Bank - User",
            "org_id" => "testbank",
            "org_url" => "testbank.com",
            "sfin_url" => "https://sfin.testbank.com"
          }
        ],
        "accounts" => [
          {
            "id" => "acc_456",
            "conn_id" => "conn_2",
            "name" => "Savings",
            "currency" => "USD",
            "balance" => "5000.00",
            "available-balance" => "5000.00",
            "balance-date" => Time.current.to_i,
            "transactions" => [],
            "extra" => {}
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_difference "Simplefin::Account.count", 1 do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end
    end

    account = Simplefin::Account.find_by(remote_id: "acc_456")
    assert_equal "Savings", account.name
    assert_equal "5000.00", account.balance
    assert_equal "conn_2", account.conn_id
  end

  test "creates transactions from account data" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [
          {
            "conn_id" => "conn_3",
            "name" => "Test Bank - User",
            "org_id" => "testbank",
            "org_url" => "testbank.com",
            "sfin_url" => "https://sfin.testbank.com"
          }
        ],
        "accounts" => [
          {
            "id" => "acc_789",
            "conn_id" => "conn_3",
            "name" => "Credit Card",
            "currency" => "USD",
            "balance" => "-500.00",
            "available-balance" => "4500.00",
            "balance-date" => Time.current.to_i,
            "transactions" => [
              {
                "id" => "txn_1",
                "posted" => (Time.current - 3.days).to_i,
                "amount" => "-50.00",
                "description" => "Uncle Frank's Bait Shop",
                "transacted-at" => (Time.current - 3.days).to_i,
                "pending" => false,
                "extra" => {}
              }
            ],
            "extra" => {}
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_difference "Simplefin::Transaction.count", 1 do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end
    end

    transaction = Simplefin::Transaction.find_by(remote_id: "txn_1")
    assert_equal "-50.00", transaction.amount
    assert_equal "Uncle Frank's Bait Shop", transaction.description
    assert_equal false, transaction.pending
  end

  test "clears errlist when API has no errors" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      { "accounts" => [], "connections" => [] }
    end

    SimplefinClient.stub :new, mock_client do
      @simplefin_connection.update!(errlist: [ { "code" => "con.auth", "msg" => "Previous Error" } ])
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      @simplefin_connection.reload
      assert_equal [], @simplefin_connection.errlist
    end
  end

  test "sets errlist on connection when API returns errors" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [
          { "code" => "con.auth", "msg" => "Login failed", "conn_id" => "conn_1" }
        ],
        "accounts" => [],
        "connections" => []
      }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      @simplefin_connection.reload
      assert_equal 1, @simplefin_connection.errlist.length
      assert_equal "con.auth", @simplefin_connection.errlist.first["code"]
      assert_equal "Login failed", @simplefin_connection.errlist.first["msg"]
    end
  end

  test "updates existing accounts and transactions" do
    # Create existing account
    existing_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_existing",
      name: "Old Name",
      currency: "USD",
      balance: "100.00"
    )

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [
          {
            "conn_id" => "conn_new",
            "name" => "New Bank - User",
            "org_id" => "newbank",
            "org_url" => "newbank.com",
            "sfin_url" => "https://sfin.newbank.com"
          }
        ],
        "accounts" => [
          {
            "id" => "acc_existing",
            "conn_id" => "conn_new",
            "name" => "New Name",
            "currency" => "USD",
            "balance" => "200.00",
            "available-balance" => "200.00",
            "balance-date" => Time.current.to_i,
            "transactions" => [],
            "extra" => {}
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_no_difference "Simplefin::Account.count" do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end
    end

    existing_account.reload
    assert_equal "newbank.com", existing_account.org["org_url"]
    assert_equal "New Name", existing_account.name
    assert_equal "200.00", existing_account.balance
    assert_equal "conn_new", existing_account.conn_id
  end

  test "populates org from connections array by conn_id" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [
          {
            "conn_id" => "conn_abc",
            "name" => "My Bank - Jeff",
            "org_id" => "mybank",
            "org_url" => "mybank.com",
            "sfin_url" => "https://sfin.mybank.com"
          }
        ],
        "accounts" => [
          {
            "id" => "acc_org_test",
            "conn_id" => "conn_abc",
            "name" => "Checking",
            "currency" => "USD",
            "balance" => "100.00",
            "available-balance" => "100.00",
            "balance-date" => Time.current.to_i,
            "transactions" => [],
            "extra" => {}
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
    end

    account = Simplefin::Account.find_by(remote_id: "acc_org_test")
    assert_equal "conn_abc", account.conn_id
    assert_equal "My Bank - Jeff", account.org["name"]
    assert_equal "mybank", account.org["org_id"]
    assert_equal "mybank.com", account.org["org_url"]
  end

  test "enqueues import jobs for linked accounts after refresh" do
    # linked_one fixture (remote_id: remote_id_1) is linked to linked_asset via Account.sourceable
    linked_sf_account = simplefin_accounts(:linked_one)

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [],
        "accounts" => [
          {
            "id" => "remote_id_1",
            "name" => "Test Checking",
            "currency" => "USD",
            "balance" => "1000.00",
            "transactions" => []
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_enqueued_with(job: Simplefin::ImportTransactionsJob, args: [ { simplefin_account_id: linked_sf_account.id } ]) do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end
    end
  end

  test "does not enqueue import jobs for unlinked accounts after refresh" do
    # Unlink all accounts first
    Account.where(sourceable_type: "Simplefin::Account").update_all(sourceable_id: nil, sourceable_type: nil)

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [],
        "accounts" => [
          {
            "id" => "remote_id_2",
            "name" => "Test Savings",
            "currency" => "USD",
            "balance" => "5000.00",
            "transactions" => []
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      assert_no_enqueued_jobs(only: Simplefin::ImportTransactionsJob) do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end
    end
  end

  test "sets last_seen_at on accounts that appear in the response" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [],
        "accounts" => [
          {
            "id" => "acc_seen",
            "name" => "Seen",
            "currency" => "USD",
            "balance" => "1.00",
            "transactions" => []
          }
        ]
      }
    end

    travel_to Time.zone.local(2026, 4, 27, 12, 0, 0) do
      SimplefinClient.stub :new, mock_client do
        Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      end

      seen_account = Simplefin::Account.find_by(remote_id: "acc_seen")
      assert_equal Time.current, seen_account.last_seen_at
    end
  end

  test "does not bump last_seen_at on accounts absent from the response" do
    stale_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_stale",
      last_seen_at: 3.days.ago
    )
    original_last_seen = stale_account.last_seen_at

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      { "errlist" => [], "connections" => [], "accounts" => [] }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
    end

    stale_account.reload
    assert_in_delta original_last_seen, stale_account.last_seen_at, 1.second
  end

  test "uses the same timestamp for account last_seen_at and connection refreshed_at" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errlist" => [],
        "connections" => [],
        "accounts" => [
          {
            "id" => "acc_sync",
            "name" => "Sync",
            "currency" => "USD",
            "balance" => "1.00",
            "transactions" => []
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
    end

    @simplefin_connection.reload
    synced_account = Simplefin::Account.find_by(remote_id: "acc_sync")
    assert_equal @simplefin_connection.refreshed_at, synced_account.last_seen_at
  end

  test "continues to next account when one account raises an error" do
    mock_client = Minitest::Mock.new

    save_count = 0

    def mock_client.accounts(start_date:)
      {
        "connections" => [],
        "errlist" => [],
        "accounts" => [
          {
            "id" => "acc_failing",
            "name" => "Failing Account",
            "currency" => "USD",
            "balance" => "invalid",
            "transactions" => nil # This will cause a NoMethodError when iterating
          },
          {
            "id" => "acc_working",
            "name" => "Working Account",
            "currency" => "USD",
            "balance" => "500.00",
            "transactions" => []
          }
        ]
      }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
    end

    # The working account was saved despite the first one failing
    assert Simplefin::Account.exists?(remote_id: "acc_working")

    # Connection still updated
    @simplefin_connection.reload
    assert_not_nil @simplefin_connection.refreshed_at
  end
end
