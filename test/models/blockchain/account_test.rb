require "test_helper"

class Blockchain::AccountTest < ActiveSupport::TestCase
  setup do
    @blockchain_account = blockchain_accounts(:xpub_wallet_btc)
  end

  test "is registered for reconciliation" do
    assert_includes AggregatorLinkable.registry, Blockchain::Account
    assert_equal Blockchain::Transaction, Blockchain::Account.transaction_class
  end

  test "uses the wallet label as its institution" do
    assert_equal "Cold storage", @blockchain_account.institution_name
  end

  test "resolves its currency and computes balance_minor in satoshis" do
    assert_equal currencies(:btc), @blockchain_account.ledger_currency
    assert_equal 1_540_000, @blockchain_account.balance_minor
  end

  test "current? compares last_seen_at with the connection's refresh" do
    assert @blockchain_account.current?
    assert_not @blockchain_account.current?(1.day.from_now)
    assert_not Blockchain::Account.new.current?
  end

  test "complete chain history suggests a zero opening balance" do
    suggestion = @blockchain_account.suggested_opening_balance

    assert_equal 0, suggestion[:amount]
    assert_equal Time.zone.parse("2026-04-20").beginning_of_day, suggestion[:transacted_at]
  end

  test "no opening balance suggestion without a known currency" do
    @blockchain_account.currency = "ZZZ"

    assert_nil @blockchain_account.suggested_opening_balance
  end

  test "amounts stay in the wallet's currency even if the link points elsewhere" do
    usd_account = users(:one).accounts.create!(name: "Crypto (USD)", kind: :asset, currency: currencies(:usd))
    AccountSource.create!(account: usd_account, sourceable: @blockchain_account)

    assert_equal currencies(:btc), @blockchain_account.reload.ledger_currency
  end

  test "a ledger account linked to a wallet cannot switch currency" do
    ledger_account = users(:one).accounts.create!(name: "Cold storage", kind: :asset, currency: currencies(:btc))
    AccountSource.create!(account: ledger_account, sourceable: @blockchain_account)

    assert_not ledger_account.update(currency: currencies(:usd))
    assert_includes ledger_account.errors[:currency], "must stay BTC while a wallet is linked"
    assert ledger_account.reload.update(name: "Renamed"), "other edits still work"
  end

  test "wallet identifiers are filtered from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("blockchain_connection" => { "identifier" => "zprv-pasted-by-mistake", "name" => "Vault" })

    assert_equal "[FILTERED]", filtered["blockchain_connection"]["identifier"]
    assert_equal "Vault", filtered["blockchain_connection"]["name"]
    assert_includes Blockchain::Connection.new(identifier: "zprv-pasted-by-mistake").inspect, "identifier: [FILTERED]"
  end
end
