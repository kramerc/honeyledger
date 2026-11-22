require "test_helper"

class Blockchain::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @blockchain_account = blockchain_accounts(:xpub_wallet_btc)
    @ledger_account = @user.accounts.create!(name: "Cold storage", kind: :asset, currency: currencies(:btc))
    AccountSource.create!(account: @ledger_account, sourceable: @blockchain_account)
  end

  test "imports receipts, sends, and fees so the ledger matches the chain balance" do
    assert_difference "Transaction.count", 3 do
      perform
    end

    received = blockchain_transactions(:received).ledger_transactions.sole
    assert_equal @ledger_account, received.dest_account
    assert_equal "Bitcoin received", received.src_account.name
    assert_equal "revenue", received.src_account.kind
    assert_equal 2_000_000, received.amount_minor
    assert_equal "Received from bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el", received.description
    assert_equal Time.zone.parse("2026-04-20 12:00"), received.transacted_at
    assert_not_nil received.cleared_at

    sent = blockchain_transactions(:sent).ledger_transactions.sole
    assert_equal @ledger_account, sent.src_account
    assert_equal "Bitcoin sent", sent.dest_account.name
    assert_equal 450_000, sent.amount_minor

    fee = blockchain_transactions(:sent_fee).ledger_transactions.sole
    assert_equal @ledger_account, fee.src_account
    assert_equal "Network fees", fee.dest_account.name
    assert_equal "expense", fee.dest_account.kind
    assert_equal 10_000, fee.amount_minor

    assert_equal @blockchain_account.balance_minor, @ledger_account.reload.balance_minor
  end

  test "sends to different addresses share one counterpart account" do
    Blockchain::Transaction.create!(
      account: @blockchain_account, remote_id: "33" * 32, txid: "33" * 32, kind: "transfer",
      amount: "-0.001", counterparty: "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH",
      transacted_at: Time.zone.parse("2026-04-23 12:00"), confirmed: true, synced_at: Time.current
    )

    perform

    assert_equal 1, @user.accounts.where(name: "Bitcoin sent").count
  end

  test "an import rule on the counterparty address routes the transfer" do
    exchange_deposits = @user.accounts.create!(name: "Exchange purchases", kind: :expense, currency: currencies(:btc))
    @user.import_rules.create!(match_pattern: "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g", match_type: :contains, account: exchange_deposits)

    perform

    assert_equal exchange_deposits, blockchain_transactions(:sent).ledger_transactions.sole.dest_account
    assert_equal "Network fees", blockchain_transactions(:sent_fee).ledger_transactions.sole.dest_account.name
  end

  test "unconfirmed rows are not imported" do
    blockchain_transactions(:received).update!(confirmed: false)

    perform

    assert_empty blockchain_transactions(:received).reload.ledger_transactions
  end

  test "a changed row re-syncs its canonical ledger transaction without a duplicate" do
    perform
    blockchain_transaction = blockchain_transactions(:sent)
    blockchain_transaction.update!(amount: "-0.0046", synced_at: 1.minute.from_now)

    assert_no_difference "Transaction.count" do
      perform
    end

    assert_equal 460_000, blockchain_transaction.ledger_transactions.sole.amount_minor
  end

  test "does nothing for an unlinked account" do
    AccountSource.where(sourceable: @blockchain_account).destroy_all

    assert_no_difference "Transaction.count" do
      perform
    end
  end

  test "linking a wallet account enqueues its import" do
    ledger_account = @user.accounts.create!(name: "Second wallet", kind: :asset, currency: currencies(:btc))
    blockchain_account = blockchain_connections(:xpub_wallet).accounts.create!(remote_id: "OTHER", name: "Bitcoin", currency: "BTC")

    assert_enqueued_with(job: Blockchain::ImportTransactionsJob, args: [ { blockchain_account_id: blockchain_account.id } ]) do
      AccountSource::Attach.call(account: ledger_account, sourceable: blockchain_account)
    end
  end

  private

    def perform
      Blockchain::ImportTransactionsJob.perform_now(blockchain_account_id: @blockchain_account.id)
    end
end
