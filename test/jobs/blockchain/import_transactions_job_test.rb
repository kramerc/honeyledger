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

  test "a fiat account with a default counterpart name is not booked into" do
    usd_fees = @user.accounts.create!(name: "Network fees", kind: :expense, currency: currencies(:usd))

    perform

    fee = blockchain_transactions(:sent_fee).ledger_transactions.sole
    assert_equal "Network fees (BTC)", fee.dest_account.name
    assert_equal currencies(:btc), fee.currency
    assert_equal 10_000, fee.amount_minor
    assert_equal 0, usd_fees.reload.balance_minor
  end

  test "keeps disambiguating while suffixed names are also taken in another currency" do
    @user.accounts.create!(name: "Network fees", kind: :expense, currency: currencies(:usd))
    @user.accounts.create!(name: "Network fees (BTC)", kind: :expense, currency: currencies(:usd))

    perform

    fee = blockchain_transactions(:sent_fee).ledger_transactions.sole
    assert_equal "Network fees (BTC 2)", fee.dest_account.name
    assert_equal currencies(:btc), fee.currency
  end

  test "skips a row with no free counterpart name, imports the rest, and says why" do
    names = [ "Network fees", "Network fees (BTC)" ] + (2..9).map { |number| "Network fees (BTC #{number})" }
    names.each { |name| @user.accounts.create!(name: name, kind: :expense, currency: currencies(:usd)) }

    assert_difference "Transaction.count", 2 do # the receipt and the send; the fee has nowhere to go
      perform
    end

    assert_empty blockchain_transactions(:sent_fee).ledger_transactions
    assert_match(/Some transactions were not imported/, blockchain_connections(:xpub_wallet).reload.error)
  end

  test "rows are not imported while the link is to an account in another currency" do
    AccountSource.where(sourceable: @blockchain_account).destroy_all
    usd_account = @user.accounts.create!(name: "Crypto (USD)", kind: :asset, currency: currencies(:usd))
    AccountSource.create!(account: usd_account, sourceable: @blockchain_account) # bypasses the link checks

    assert_no_difference "Transaction.count" do
      perform
    end
    assert_match(/Crypto \(USD\) is not in BTC/, blockchain_connections(:xpub_wallet).reload.error)
  end

  test "a successful import clears an error the import wrote earlier, not a refresh error" do
    connection = blockchain_connections(:xpub_wallet)
    connection.update!(error: "Not imported: Crypto (USD) is not in BTC. Link the wallet to a BTC account.")

    perform

    assert_nil connection.reload.error, "relinked to a BTC account, the stale import error is gone"

    connection.update!(error: "The explorer returned HTTP 503")
    perform
    assert_equal "The explorer returned HTTP 503", connection.reload.error, "a refresh error is left for the refresh to clear"
  end

  test "a rule pointing at an account in another currency is not applied" do
    usd_gifts = @user.accounts.create!(name: "Gifts", kind: :expense, currency: currencies(:usd))
    @user.import_rules.create!(match_pattern: "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g", match_type: :contains, account: usd_gifts)

    perform

    sent = blockchain_transactions(:sent).ledger_transactions.sole
    assert_equal "Bitcoin sent", sent.dest_account.name
    assert_equal currencies(:btc), sent.currency
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

  test "a matching manual entry absorbs the row instead of duplicating it" do
    sent = blockchain_transactions(:sent)
    manual = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @user.accounts.create!(name: "Hardware", kind: :expense, currency: currencies(:btc)),
      amount_minor: 450_000, currency: currencies(:btc), description: sent.resolved_description, transacted_at: sent.transacted_at
    )

    assert_difference "Transaction.count", 2 do # the receipt and the fee; the send attaches to the manual entry
      perform
    end

    assert_equal [ manual ], sent.ledger_transactions.to_a
  end

  test "a concurrent attach rolls back the row on either branch" do
    sent = blockchain_transactions(:sent)
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @user.accounts.create!(name: "Hardware", kind: :expense, currency: currencies(:btc)),
      amount_minor: 450_000, currency: currencies(:btc), description: sent.resolved_description, transacted_at: sent.transacted_at
    )

    assert_no_difference [ "Transaction.count", "TransactionSource.count" ] do
      TransactionSource::Attach.stub :call, ->(**) { raise TransactionSource::Attach::MismatchedTransaction, "race" } do
        perform
      end
    end
  end

  test "a secondary source only stamps synced_at on resync" do
    perform
    sent = blockchain_transactions(:sent)
    ledger_transaction = sent.ledger_transactions.sole
    # Another source attached earlier, so the wallet row is the secondary one.
    other_feed = blockchain_connections(:address_wallet).accounts.create!(remote_id: "BTC", name: "Bitcoin", currency: "BTC")
    other_row = other_feed.transactions.create!(remote_id: "44" * 32, txid: "44" * 32, amount: "-0.0045", confirmed: true)
    TransactionSource.create!(ledger_transaction: ledger_transaction, sourceable: other_row, created_at: 1.day.ago)
    sent.update!(amount: "-0.0099", synced_at: 2.minutes.from_now)

    perform

    ledger_transaction.reload
    assert_equal 450_000, ledger_transaction.amount_minor, "a secondary source never overwrites canonical fields"
    assert_operator ledger_transaction.synced_at, :>=, sent.reload.synced_at
  end

  test "an exclude rule on the counterparty address excludes the transfer" do
    @user.import_rules.create!(match_pattern: "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g", match_type: :contains, exclude: true)

    perform

    assert blockchain_transactions(:sent).ledger_transactions.sole.excluded?
    assert_not blockchain_transactions(:sent_fee).ledger_transactions.sole.excluded?
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

  test "a receipt into another wallet does not merge with an equal wallet fee" do
    perform
    fee = blockchain_transactions(:sent_fee).ledger_transactions.sole
    other_wallet = @user.accounts.create!(name: "Hot wallet", kind: :asset, currency: currencies(:btc))
    revenue = @user.accounts.create!(name: "Incoming", kind: :revenue, currency: currencies(:btc))
    receipt = Transaction.create!(user: @user, src_account: revenue, dest_account: other_wallet, amount_minor: fee.amount_minor,
                                  currency: currencies(:btc), description: "Received", transacted_at: fee.transacted_at)

    Transaction::AutoMerge.call(receipt, rule_account: @ledger_account)

    assert_nil fee.reload.merged_into_id, "the fee stays an expense"
    assert_equal 10_000, fee.amount_minor
  end

  test "retroactive rules never offer a wallet fee as a merge candidate" do
    perform
    fee = blockchain_transactions(:sent_fee).ledger_transactions.sole
    other_wallet = @user.accounts.create!(name: "Hot wallet", kind: :asset, currency: currencies(:btc))
    AccountSource.create!(account: other_wallet, sourceable: blockchain_connections(:xpub_wallet).accounts.create!(remote_id: "SECOND", name: "Bitcoin", currency: "BTC"))
    revenue = @user.accounts.create!(name: "Incoming", kind: :revenue, currency: currencies(:btc))
    create_sourced_transaction(
      user: @user, src_account: revenue, dest_account: other_wallet, amount_minor: fee.amount_minor, currency: currencies(:btc),
      description: "Top-up from cold storage", transacted_at: fee.transacted_at,
      sourceable: Blockchain::Transaction.create!(account: Blockchain::Account.find_by!(remote_id: "SECOND"), remote_id: "55" * 32, txid: "55" * 32, amount: "0.0001", confirmed: true)
    )
    ImportRule.create!(user: @user, account: @ledger_account, match_pattern: "Top-up from cold storage", match_type: :exact)

    change = ImportRule::RetroactiveApply.new(user: @user).preview.find { |candidate| candidate.transaction.description == "Top-up from cold storage" }

    assert_not_nil change
    assert_nil change.merge_candidate, "the fee is not a transfer leg"
  end

  test "an Ethereum wallet imports to the wei, with gas in an ETH fee account" do
    user = users(:two)
    eth_account = blockchain_accounts(:eth_wallet_eth)
    ledger_account = user.accounts.create!(name: "Hot wallet", kind: :asset, currency: currencies(:eth))
    AccountSource.create!(account: ledger_account, sourceable: eth_account)
    btc_fees = user.accounts.create!(name: "Network fees", kind: :expense, currency: currencies(:btc))

    assert_difference "Transaction.count", 4 do
      Blockchain::ImportTransactionsJob.perform_now(blockchain_account_id: eth_account.id)
    end

    received = blockchain_transactions(:eth_received).ledger_transactions.sole
    assert_equal "Ethereum received", received.src_account.name
    assert_equal 1_500_000_000_000_000_000, received.amount_minor
    assert_equal "Received from 0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359", received.description

    assert_equal "Ethereum sent", blockchain_transactions(:eth_sent).ledger_transactions.sole.dest_account.name
    assert_equal 1, blockchain_transactions(:eth_dust).ledger_transactions.sole.amount_minor

    fee = blockchain_transactions(:eth_sent_fee).ledger_transactions.sole
    assert_equal "Network fees (ETH)", fee.dest_account.name
    assert_equal 441_000_000_000_000, fee.amount_minor
    assert_equal 0, btc_fees.reload.balance_minor

    assert_equal 1_249_559_000_000_000_001, ledger_account.reload.balance_minor
    assert_equal eth_account.balance_minor, ledger_account.balance_minor
  end

  private

    def perform
      Blockchain::ImportTransactionsJob.perform_now(blockchain_account_id: @blockchain_account.id)
    end
end
