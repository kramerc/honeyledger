require "test_helper"

class Lunchflow::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)

    # Clear any aggregator transactions that would be imported from fixtures (linked via Account.sourceable)
    linked_lf_ids = Account.where(sourceable_type: "Lunchflow::Account").where.not(sourceable_id: nil).pluck(:sourceable_id)
    Lunchflow::Transaction.where(account_id: linked_lf_ids).destroy_all
  end

  test "imports expense transaction (negative amount)" do
    lf_account, lf_bank_account = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_expense_1",
      amount: "-50.00",
      currency: "USD",
      description: "Coffee Shop",
      merchant: "Starbucks",
      pending: false,
      date: 2.days.ago.to_date
    )

    assert_difference "Transaction.count", 1 do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal lf_bank_account, transaction.src_account
    assert_equal "Starbucks", transaction.description
    assert_equal "expense", transaction.dest_account.kind
    assert_equal 5000, transaction.amount_minor
    assert_not_nil transaction.cleared_at
  end

  test "imports revenue transaction (positive amount)" do
    lf_account, lf_bank_account = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_revenue_1",
      amount: "2500.00",
      currency: "USD",
      description: "Salary",
      merchant: nil,
      pending: false,
      date: 3.days.ago.to_date
    )

    assert_difference "Transaction.count", 1 do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal lf_bank_account, transaction.dest_account
    assert_equal "Salary", transaction.description
    assert_equal "revenue", transaction.src_account.kind
    assert_equal 250000, transaction.amount_minor
  end

  test "uses merchant over description" do
    lf_account, _ = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_merchant_1",
      amount: "-25.00",
      currency: "USD",
      description: "POS DEBIT 12345",
      merchant: "Whole Foods",
      pending: false,
      date: 1.day.ago.to_date
    )

    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_equal "Whole Foods", transaction.description
  end

  test "pending transaction has nil cleared_at" do
    lf_account, _ = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_pending_1",
      amount: "-15.00",
      currency: "USD",
      description: "Pending Purchase",
      pending: true,
      date: Date.current
    )

    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_nil transaction.cleared_at
  end

  test "uses account rule to route expense transaction" do
    lf_account, _ = create_linked_lunchflow_account

    grocery_account = Account.create!(user: @user, currency: @currency, name: "Groceries", kind: :expense)
    ImportRule.create!(user: @user, account: grocery_account, match_pattern: "WHOLEFDS", match_type: :contains)

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: "lf_rule_expense",
      amount: "-45.00",
      currency: "USD",
      description: "WHOLEFDS MKT #10234",
      date: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_equal grocery_account, transaction.dest_account
  end

  test "auto-merges when import rule matches balance sheet account and duplicate exists" do
    lf_account_a, bank_a = create_linked_lunchflow_account(remote_id: 801, name: "Bank A")
    lf_account_b, bank_b = create_linked_lunchflow_account(remote_id: 802, name: "Bank B")

    # Import from bank_b first (no rule) — creates revenue → bank_b
    Lunchflow::Transaction.create!(
      account: lf_account_b,
      remote_id: "lf_dup",
      amount: "500.00",
      currency: "USD",
      description: "TRANSFER FROM A",
      date: 2.days.ago,
      pending: false
    )
    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account_b.id)

    # Create import rule mapping "TRANSFER TO B" to bank_b (asset)
    ImportRule.create!(user: @user, account: bank_b, match_pattern: "TRANSFER TO B", match_type: :contains)

    # Import from bank_a (BS rule) — creates expense first, then auto-merge finds the
    # revenue→bank_b duplicate and merges both into a bank_a→bank_b transfer
    Lunchflow::Transaction.create!(
      account: lf_account_a,
      remote_id: "lf_transfer",
      amount: "-500.00",
      currency: "USD",
      description: "TRANSFER TO B",
      date: 2.days.ago,
      pending: false
    )

    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account_a.id)

    # Both originals should be zeroed and merged via Transaction::Merge
    unmerged = @user.transactions.unmerged.where(amount_minor: 50000)
    assert_equal 1, unmerged.count

    merged = unmerged.first
    assert_equal bank_a, merged.src_account
    assert_equal bank_b, merged.dest_account
    assert_equal 50000, merged.amount_minor
  end

  test "skips excluded transactions during reimport" do
    lf_account, _ = create_linked_lunchflow_account

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: 999,
      amount: "-50.00",
      currency: "USD",
      description: "Excluded Transaction",
      merchant: "Excluded Merchant",
      pending: false,
      date: 2.days.ago.to_date
    )

    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    transaction = Transaction.find_by(sourceable: lf_transaction)

    Transaction::Exclude.new(transaction, user: @user).call
    original_synced_at = transaction.reload.synced_at

    travel 2.seconds
    lf_transaction.update!(synced_at: Time.current)

    assert_no_difference "Transaction.count" do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    assert_equal original_synced_at, transaction.reload.synced_at
  end

  test "exclude rule auto-excludes imported transaction" do
    lf_account, _ = create_linked_lunchflow_account

    ImportRule.create!(user: @user, match_pattern: "SPAM", match_type: :contains, exclude: true)

    lf_transaction = Lunchflow::Transaction.create!(
      account: lf_account,
      remote_id: 998,
      amount: "-10.00",
      currency: "USD",
      description: "SPAM Transaction",
      merchant: "SPAM Merchant",
      pending: false,
      date: 1.day.ago.to_date
    )

    assert_difference "Transaction.count", 1 do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert transaction.excluded?
  end

  test "aggregates sidebar broadcasts to one per affected account regardless of row count" do
    lf_account, lf_bank_account = create_linked_lunchflow_account

    expense_account = Account.create!(user: @user, currency: @currency, name: "Coffee", kind: :expense)

    3.times do |i|
      Lunchflow::Transaction.create!(
        account: lf_account,
        remote_id: "lf_agg_#{i}",
        amount: "-#{i + 1}.00",
        currency: "USD",
        description: "Coffee",
        merchant: "Coffee",
        pending: false,
        date: i.days.ago.to_date
      )
    end

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    targets = streams.select { |s| s["action"] == "update" }.map { |s| s["target"] }.sort
    expected = [
      ActionView::RecordIdentifier.dom_id(lf_bank_account, :sidebar_link),
      ActionView::RecordIdentifier.dom_id(expense_account, :sidebar_link)
    ].sort
    assert_equal expected, targets
  end

  test "broadcasts nothing when there are no aggregator transactions to import" do
    lf_account, _ = create_linked_lunchflow_account

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    assert_empty streams
  end

  test "auto-merge broadcasts include counterparty accounts from merged candidates" do
    lf_account_a, bank_a = create_linked_lunchflow_account(remote_id: 901, name: "Bank A")
    lf_account_b, bank_b = create_linked_lunchflow_account(remote_id: 902, name: "Bank B")

    # First import from bank_b: creates a revenue -> bank_b transaction; revenue account is
    # auto-created here and will be affected again when Merge zeroes out the candidate.
    Lunchflow::Transaction.create!(
      account: lf_account_b,
      remote_id: "broadcast_dup",
      amount: "500.00",
      currency: "USD",
      description: "TRANSFER FROM A",
      date: 2.days.ago,
      pending: false
    )
    Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account_b.id)
    revenue_counterparty = @user.accounts.find_by!(name: "TRANSFER FROM A", kind: :revenue)

    # Rule maps TRANSFER TO B -> bank_b, so auto-merge kicks in on the bank_a import.
    ImportRule.create!(user: @user, account: bank_b, match_pattern: "TRANSFER TO B", match_type: :contains)

    Lunchflow::Transaction.create!(
      account: lf_account_a,
      remote_id: "broadcast_transfer",
      amount: "-500.00",
      currency: "USD",
      description: "TRANSFER TO B",
      date: 2.days.ago,
      pending: false
    )

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Lunchflow::ImportTransactionsJob.perform_now(lunchflow_account_id: lf_account_a.id)
    end

    targets = streams.select { |s| s["action"] == "update" }.map { |s| s["target"] }
    # Broadcasts must cover every real account whose balance moved during the job:
    # the two bank accounts from the final transfer, plus the revenue counterparty
    # whose balance was reversed when its transaction was absorbed into the merge.
    assert_includes targets, ActionView::RecordIdentifier.dom_id(bank_a, :sidebar_link)
    assert_includes targets, ActionView::RecordIdentifier.dom_id(bank_b, :sidebar_link)
    assert_includes targets, ActionView::RecordIdentifier.dom_id(revenue_counterparty, :sidebar_link)
    # Each affected account should appear exactly once (aggregation).
    assert_equal targets.uniq.size, targets.size
  end

  private

    def create_linked_lunchflow_account(remote_id: 901, name: "LF Test Checking")
      lf_account = Lunchflow::Account.create!(
        connection: lunchflow_connections(:one),
        remote_id: remote_id,
        name: name,
        currency: "USD",
        balance: "1000.00"
      )

      lf_bank_account = Account.create!(
        user: @user,
        currency: @currency,
        name: "Linked #{name}",
        kind: :asset,
        sourceable: lf_account
      )

      [ lf_account, lf_bank_account ]
    end
end
