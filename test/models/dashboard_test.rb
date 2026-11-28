require "test_helper"

class DashboardTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @user = User.create!(email: "dashboard@example.com", password: "password123")
    @dashboard = Dashboard.new(@user)
  end

  # Empty state

  test "is empty without a balance-sheet account" do
    @user.accounts.create!(name: "Sample Vendor", kind: :expense, currency: currencies(:usd))

    assert @dashboard.empty?
  end

  test "is not empty once the user has an asset account" do
    create_account(:asset, 0)

    assert_not @dashboard.empty?
  end

  # Net worth

  test "net worth subtracts liabilities, which carry a negative balance while owed" do
    create_account(:asset, 150_000, name: "Checking")
    create_account(:asset, 50_000, name: "Savings")
    create_account(:liability, -30_000, name: "Card")

    row = @dashboard.net_worth.sole
    assert_equal currencies(:usd), row.currency
    assert_equal 200_000, row.assets_minor
    assert_equal(-30_000, row.liabilities_minor)
    assert_equal 170_000, row.net_minor
  end

  test "net worth leaves out equity, expense, revenue, and virtual accounts" do
    create_account(:asset, 10_000)
    create_account(:equity, 99_000, name: "Equity")
    create_account(:expense, 99_000, name: "Sample Vendor")
    create_account(:revenue, 99_000, name: "Sample Employer")
    @user.accounts.create!(name: "Opening Balance", kind: :asset, virtual: true, balance_minor: 99_000)

    assert_equal 10_000, @dashboard.net_worth.sole.net_minor
  end

  test "net worth keeps one row per currency without converting between them" do
    create_account(:asset, 10_000, name: "Dollars")
    create_account(:asset, 25_000_000, name: "Coins", currency: currencies(:btc))
    create_account(:liability, -2_000, name: "Euro card", currency: currencies(:eur))

    rows = @dashboard.net_worth
    assert_equal %w[ BTC EUR USD ], rows.map { |row| row.currency.code }
    assert_equal [ 25_000_000, -2_000, 10_000 ], rows.map(&:net_minor)
    assert_equal 0, rows.second.assets_minor
  end

  test "net worth never includes another user's accounts" do
    create_account(:asset, 10_000)

    assert_equal 10_000, @dashboard.net_worth.sole.net_minor
    assert Dashboard.new(users(:two)).net_worth.none? { |row| row.net_minor == 10_000 }
  end

  # Needs attention

  test "nothing needs attention without connections" do
    assert_empty @dashboard.attention_items
  end

  test "fresh, healthy connections need no attention" do
    simplefin_connection = @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: 1.hour.ago)
    lunchflow_connection = @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago)
    lunchflow_connection.accounts.create!(remote_id: 1, name: "Test Bank Checking", status: "ACTIVE", last_seen_at: 1.hour.ago)
      .then { |lunchflow_account| link(lunchflow_account) }
    simplefin_connection.accounts.create!(remote_id: "simplefin-1", name: "Old account", last_seen_at: 1.week.ago)

    assert_empty @dashboard.attention_items
  end

  test "SimpleFIN errors from the last refresh need attention" do
    @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: 1.hour.ago,
      errlist: [ { "code" => "gen.auth", "msg" => "Reauthenticate" }, { "code" => "con.auth", "msg" => "Reconnect" } ])

    item = @dashboard.attention_items.sole
    assert_equal "SimpleFIN reported 2 errors on its last refresh", item.message
    assert item.error?
    assert_equal integrations_path, item.path
  end

  test "a Lunch Flow connection error needs attention" do
    @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago, error: "Invalid API key")

    assert_equal [ "Lunch Flow: Invalid API key" ], @dashboard.attention_items.map(&:message)
  end

  test "a linked Lunch Flow account in trouble needs attention, an unlinked one does not" do
    connection = @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago)
    link(connection.accounts.create!(remote_id: 1, name: "Checking", status: "DISCONNECTED", last_seen_at: 1.hour.ago))
    link(connection.accounts.create!(remote_id: 2, name: "Savings", status: "ERROR", last_seen_at: 1.hour.ago))
    connection.accounts.create!(remote_id: 3, name: "Brokerage", status: "ERROR", last_seen_at: 1.week.ago)

    assert_equal [ "Lunch Flow account Checking is disconnected", "Lunch Flow account Savings reports an error" ],
      @dashboard.attention_items.map(&:message)
  end

  test "a wallet error, such as a balance mismatch, needs attention" do
    @user.blockchain_connections.create!(chain: "bitcoin", name: "Hot wallet", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
      refreshed_at: 1.hour.ago, error: "Balance mismatch: the chain reports more than the history adds up to")

    item = @dashboard.attention_items.sole
    assert_equal "Hot wallet: Balance mismatch: the chain reports more than the history adds up to", item.message
    assert item.error?
  end

  test "a connection not refreshed for three days needs a nudge" do
    travel_to Time.zone.local(2026, 11, 27, 12) do
      @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: 5.days.ago)
      @user.create_lunchflow_connection!(api_key: "key", refreshed_at: nil)

      items = @dashboard.attention_items
      assert_equal [ "SimpleFIN was last refreshed 5 days ago", "Lunch Flow has never been refreshed" ], items.map(&:message)
      assert items.none?(&:error?)
    end
  end

  test "a connection refreshed just inside three days is not stale" do
    travel_to Time.zone.local(2026, 11, 27, 12) do
      @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: Dashboard::STALE_AFTER.ago + 1.minute)

      assert_empty @dashboard.attention_items
    end
  end

  test "unlinked aggregator accounts are counted as the integrations page lists them" do
    simplefin_connection = @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: 1.hour.ago)
    simplefin_connection.accounts.create!(remote_id: "simplefin-1", name: "Current", last_seen_at: 1.hour.ago)
    simplefin_connection.accounts.create!(remote_id: "simplefin-2", name: "Dropped by the bank", last_seen_at: 1.week.ago)
    lunchflow_connection = @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago)
    lunchflow_connection.accounts.create!(remote_id: 1, name: "Current", status: "ACTIVE", last_seen_at: 1.hour.ago)
    link(lunchflow_connection.accounts.create!(remote_id: 2, name: "Linked", status: "ACTIVE", last_seen_at: 1.hour.ago))
    wallet = @user.blockchain_connections.create!(chain: "bitcoin", name: "Cold storage", identifier: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", refreshed_at: 1.hour.ago)
    wallet.accounts.create!(remote_id: "BTC", name: "Bitcoin", currency: "BTC")

    item = @dashboard.attention_items.sole
    assert_equal "3 aggregator accounts aren't linked to a ledger account", item.message
    assert_not item.error?
  end

  test "a single unlinked aggregator account reads in the singular" do
    connection = @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago)
    connection.accounts.create!(remote_id: 1, name: "Current", status: "ACTIVE", last_seen_at: 1.hour.ago)

    assert_equal [ "1 aggregator account isn't linked to a ledger account" ], @dashboard.attention_items.map(&:message)
  end

  test "errors come before notices" do
    @user.create_simplefin_connection!(demo: true, url: "https://example.com", refreshed_at: 1.week.ago)
    @user.create_lunchflow_connection!(api_key: "key", refreshed_at: 1.hour.ago, error: "Invalid API key")

    assert_equal [ :error, :notice ], @dashboard.attention_items.map(&:severity)
  end

  test "another user's connection problems never appear" do
    users(:two).lunchflow_connection.update!(error: "Invalid API key")

    assert_empty @dashboard.attention_items
  end

  # Recent transactions

  test "recent transactions are ordered like the index and leave out merged and excluded rows" do
    checking = create_account(:asset, 0, name: "Checking")
    vendor = @user.accounts.create!(name: "Sample Vendor", kind: :expense, currency: currencies(:usd))
    older = create_transaction(checking, vendor, "Older", 2.days.ago)
    newer = create_transaction(checking, vendor, "Newer", 1.day.ago)
    excluded = create_transaction(checking, vendor, "Excluded", 1.hour.ago)
    excluded.update_columns(excluded_at: Time.current)
    merged = create_transaction(checking, vendor, "Merged", 1.hour.ago)
    merged.update_columns(merged_into_id: newer.id)

    assert_equal [ newer, older ], @dashboard.recent_transactions.to_a
  end

  test "recent transactions stop at the limit and never include another user's" do
    checking = create_account(:asset, 0, name: "Checking")
    vendor = @user.accounts.create!(name: "Sample Vendor", kind: :expense, currency: currencies(:usd))
    3.times { |index| create_transaction(checking, vendor, "Purchase #{index}", index.days.ago) }

    assert_equal 2, @dashboard.recent_transactions(limit: 2).size
    assert_equal [ @user.id ], @dashboard.recent_transactions.map(&:user_id).uniq
  end

  private

    def create_account(kind, balance_minor, name: "#{kind.to_s.humanize} account", currency: currencies(:usd))
      account = @user.accounts.create!(name: name, kind: kind, currency: currency)
      account.update_column(:balance_minor, balance_minor)
      account
    end

    def create_transaction(src_account, dest_account, description, transacted_at)
      Transaction.create!(user: @user, src_account: src_account, dest_account: dest_account, description: description,
        amount_minor: 1_000, currency: currencies(:usd), transacted_at: transacted_at)
    end

    def link(aggregator_account)
      ledger_account = @user.accounts.create!(name: "Ledger #{aggregator_account.name}", kind: :asset, currency: currencies(:usd))
      aggregator_account.account_sources.create!(account: ledger_account)
      aggregator_account
    end
end
