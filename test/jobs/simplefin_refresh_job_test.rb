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
        "errors" => [],
        "accounts" => [
          {
            "id" => "acc_123",
            "org" => {
              "domain" => "testbank.com",
              "sfin-url" => "https://sfin.testbank.com"
            },
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
        "errors" => [],
        "accounts" => [
          {
            "id" => "acc_456",
            "org" => {
              "domain" => "testbank.com",
              "sfin-url" => "https://sfin.testbank.com"
            },
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
  end

  test "creates transactions from account data" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errors" => [],
        "accounts" => [
          {
            "id" => "acc_789",
            "org" => {
              "domain" => "testbank.com",
              "sfin-url" => "https://sfin.testbank.com"
            },
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

  test "clears account errors when API has no errors" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      { "accounts" => [] }
    end

    SimplefinClient.stub :new, mock_client do
      @simplefin_connection.update!(account_errors: [ "Previous API Error" ])
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      @simplefin_connection.reload
      assert_equal [], @simplefin_connection.account_errors
    end
  end

  test "sets account errors on connection when API returns errors" do
    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      { "errors" => [ "Account Error" ], "accounts" => [] }
    end

    SimplefinClient.stub :new, mock_client do
      Simplefin::RefreshJob.perform_now(@simplefin_connection.id)
      @simplefin_connection.reload
      assert_equal [ "Account Error" ], @simplefin_connection.account_errors
    end
  end

  test "updates existing accounts and transactions" do
    # Create existing account
    existing_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_existing",
      org: {
        "domain" => "oldbank.com",
        "sfin-url" => "https://sfin.oldbank.com"
      },
      name: "Old Name",
      currency: "USD",
      balance: "100.00"
    )

    mock_client = Minitest::Mock.new

    def mock_client.accounts(start_date:)
      {
        "errors" => [],
        "accounts" => [
          {
            "id" => "acc_existing",
            "org" => {
              "domain" => "newbank.com",
              "sfin-url" => "https://sfin.newbank.com"
            },
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
    assert_equal "newbank.com", existing_account.org["domain"]
    assert_equal "New Name", existing_account.name
    assert_equal "200.00", existing_account.balance
  end
end
