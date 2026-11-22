require "test_helper"

class Blockchain::RefreshJobTest < ActiveJob::TestCase
  Scanner = Blockchain::Bitcoin::Scanner

  setup do
    @connection = blockchain_connections(:address_wallet)
  end

  test "upserts the native account and its rows" do
    result = Scanner::Result.new(used_addresses: 1, balance: "0.00039", rows: [
      row("aa", "transfer", "0.001", counterparty: "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH"),
      row("bb", "transfer", "-0.0006"),
      row("bb:fee", "fee", "-0.00001", txid: "bb")
    ])

    Scanner.stub :call, result do
      Blockchain::RefreshJob.perform_now(@connection.id)
    end

    account = @connection.accounts.sole
    assert_equal [ "BTC", "Bitcoin", "BTC", "0.00039" ], [ account.remote_id, account.name, account.currency, account.balance ]
    assert_not_nil account.balance_changed_at
    assert_equal %w[aa bb bb:fee], account.transactions.order(:remote_id).pluck(:remote_id)
    assert_equal "fee", account.transactions.find_by(remote_id: "bb:fee").kind
    assert_nil @connection.reload.error
    assert_not_nil @connection.refreshed_at
  end

  test "an unchanged row keeps its synced_at" do
    result = Scanner::Result.new(used_addresses: 1, balance: "0.001", rows: [ row("aa", "transfer", "0.001") ])

    Scanner.stub :call, result do
      Blockchain::RefreshJob.perform_now(@connection.id)
    end
    blockchain_transaction = @connection.transactions.sole
    blockchain_transaction.update_column(:synced_at, 1.week.ago)

    assert_no_changes -> { blockchain_transaction.reload.synced_at } do
      Scanner.stub :call, result do
        Blockchain::RefreshJob.perform_now(@connection.id)
      end
    end
  end

  test "enqueues an import only for a linked account" do
    connection = blockchain_connections(:xpub_wallet)
    result = Scanner::Result.new(used_addresses: 1, balance: "0.0154", rows: [])

    Scanner.stub :call, result do
      assert_no_enqueued_jobs(only: Blockchain::ImportTransactionsJob) do
        Blockchain::RefreshJob.perform_now(connection.id)
      end

      ledger_account = users(:one).accounts.create!(name: "Cold storage", kind: :asset, currency: currencies(:btc))
      AccountSource.create!(account: ledger_account, sourceable: blockchain_accounts(:xpub_wallet_btc))

      assert_enqueued_with(job: Blockchain::ImportTransactionsJob, args: [ { blockchain_account_id: blockchain_accounts(:xpub_wallet_btc).id } ]) do
        Blockchain::RefreshJob.perform_now(connection.id)
      end
    end
  end

  test "drops a vanished row that was never imported and keeps an imported one" do
    connection = blockchain_connections(:xpub_wallet)
    imported = blockchain_transactions(:sent)
    ledger_account = users(:one).accounts.create!(name: "Cold storage", kind: :asset, currency: currencies(:btc))
    AccountSource.create!(account: ledger_account, sourceable: blockchain_accounts(:xpub_wallet_btc))
    Blockchain::ImportTransactionsJob.perform_now(blockchain_account_id: blockchain_accounts(:xpub_wallet_btc).id)
    blockchain_transactions(:received).transaction_sources.destroy_all # as if never imported

    # The scanner now reports only the fee row.
    result = Scanner::Result.new(used_addresses: 1, balance: "-0.0001", rows: [
      row(blockchain_transactions(:sent_fee).remote_id, "fee", "-0.0001", txid: imported.txid)
    ])
    Scanner.stub :call, result do
      Blockchain::RefreshJob.perform_now(connection.id)
    end

    assert_not Blockchain::Transaction.exists?(blockchain_transactions(:received).id), "an unimported vanished row is removed"
    assert Blockchain::Transaction.exists?(imported.id), "an imported vanished row stays, with its ledger transaction"
    assert imported.ledger_transactions.exists?
  end

  test "an extended key with no activity explains the key type" do
    connection = blockchain_connections(:xpub_wallet)

    Scanner.stub :call, Scanner::Result.new(used_addresses: 0, balance: "0.0", rows: []) do
      Blockchain::RefreshJob.perform_now(connection.id)
    end

    assert_equal Blockchain::RefreshJob::NO_ACTIVITY_MESSAGE, connection.reload.error
  end

  test "allows one refresh per wallet at a time" do
    assert_equal 1, Blockchain::RefreshJob.concurrency_limit
    assert_equal "blockchain-refresh-7", Blockchain::RefreshJob.new(7).concurrency_key.split("/").last
  end

  test "records an explorer error on the connection" do
    Scanner.stub :call, ->(*) { raise EsploraClient::RateLimitedError, "Rate limited" } do
      Blockchain::RefreshJob.perform_now(@connection.id)
    end

    assert_equal "Rate limited", @connection.reload.error
    assert_not_nil @connection.refreshed_at
  end

  test "without an id refreshes only stale connections" do
    blockchain_connections(:xpub_wallet).update!(refreshed_at: 1.hour.ago)
    @connection.update!(refreshed_at: 2.days.ago)
    scanned = []

    Scanner.stub :call, ->(connection) { scanned << connection.id; Scanner::Result.new(used_addresses: 1, balance: "0", rows: []) } do
      Blockchain::RefreshJob.perform_now
    end

    assert_equal [ @connection.id ], scanned
  end

  private

    def row(remote_id, kind, amount, txid: remote_id, counterparty: nil)
      Scanner::Row.new(
        remote_id: remote_id, txid: txid, kind: kind, amount: amount, counterparty: counterparty,
        block_height: 800_000, transacted_at: Time.zone.parse("2026-04-20 12:00"), confirmed: true
      )
    end
end
