require "test_helper"

class Simplefin::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)

    # Clear any aggregator transactions that would be imported from fixtures (linked via Account.sourceable)
    linked_sf_ids = Account.where(sourceable_type: "Simplefin::Account").where.not(sourceable_id: nil).pluck(:sourceable_id)
    Simplefin::Transaction.where(account_id: linked_sf_ids).destroy_all
  end

  test "imports expense transaction (negative amount)" do
    sf_account, bank_account = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_expense_1",
      amount: "-50.00",
      description: "Coffee Shop",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal bank_account, transaction.src_account
    assert_equal "Coffee Shop", transaction.dest_account.name
    assert_equal "expense", transaction.dest_account.kind
    assert_equal "Coffee Shop", transaction.description
    assert_equal 5000, transaction.amount_minor # Absolute value
    assert_equal @currency, transaction.currency
    assert_not_nil transaction.transacted_at
    assert_not_nil transaction.cleared_at
    assert_not_nil transaction.synced_at
  end

  test "imports revenue transaction (positive amount)" do
    sf_account, bank_account = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_revenue_1",
      amount: "2500.00",
      description: "Salary Payment",
      posted: 3.days.ago,
      transacted_at: 3.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal bank_account, transaction.dest_account
    assert_equal "Salary Payment", transaction.src_account.name
    assert_equal "revenue", transaction.src_account.kind
    assert_equal "Salary Payment", transaction.description
    assert_equal 250000, transaction.amount_minor
    assert_equal @currency, transaction.currency
  end

  test "reuses existing expense account with same name" do
    sf_account, _ = create_linked_simplefin_account

    expense_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Grocery Store",
      kind: :expense
    )

    sf_transaction1 = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_1",
      amount: "-100.00",
      description: "Grocery Store",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    sf_transaction2 = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_2",
      amount: "-150.00",
      description: "Grocery Store",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 2 do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction1 = Transaction.find_by(sourceable: sf_transaction1)
    transaction2 = Transaction.find_by(sourceable: sf_transaction2)

    assert_equal expense_account, transaction1.dest_account
    assert_equal expense_account, transaction2.dest_account
  end

  test "updates existing transaction when SimpleFIN transaction is updated" do
    sf_account, _ = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_update",
      amount: "-75.00",
      description: "Original Description",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)

    transaction = Transaction.find_by(sourceable: sf_transaction)
    original_synced_at = transaction.synced_at

    travel 2.seconds

    sf_transaction.update!(
      amount: "-85.00",
      synced_at: Time.current
    )

    assert_no_difference "Transaction.count" do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction.reload
    assert_equal 8500, transaction.amount_minor
    assert transaction.synced_at > original_synced_at
  end

  test "skips transactions without linked account" do
    unlinked_sf_account = Simplefin::Account.create!(
      connection: simplefin_connections(:one),
      remote_id: "acc_unlinked",
      name: "Unlinked Account",
      currency: "USD",
      balance: "500.00"
    )

    _sf_transaction = Simplefin::Transaction.create!(
      account: unlinked_sf_account,
      remote_id: "txn_unlinked",
      amount: "-25.00",
      description: "Should Be Skipped",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_no_difference "Transaction.count" do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: unlinked_sf_account.id)
    end
  end

  test "handles transaction without posted date" do
    sf_account, _ = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_no_posted",
      amount: "-30.00",
      description: "No Posted Date",
      posted: nil,
      transacted_at: Time.current,
      pending: true
    )

    assert_difference "Transaction.count", 1 do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_not_nil transaction.transacted_at
    assert_nil transaction.cleared_at
  end

  test "only imports transactions that are new or updated since last sync" do
    sf_account, _ = create_linked_simplefin_account

    _sf_transaction_old = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_old",
      amount: "-50.00",
      description: "Old Transaction",
      posted: 5.days.ago,
      transacted_at: 5.days.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)

    sf_transaction_new = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_new",
      amount: "-30.00",
      description: "New Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    assert_not_nil Transaction.find_by(sourceable: sf_transaction_new)
  end

  test "uses account rule to route expense transaction" do
    sf_account, _ = create_linked_simplefin_account

    grocery_account = Account.create!(user: @user, currency: @currency, name: "Groceries", kind: :expense)
    ImportRule.create!(user: @user, account: grocery_account, match_pattern: "WHOLEFDS", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_expense",
      amount: "-45.00",
      description: "WHOLEFDS MKT #10234",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal grocery_account, transaction.dest_account
  end

  test "uses account rule to route revenue transaction" do
    sf_account, _ = create_linked_simplefin_account

    salary_account = Account.create!(user: @user, currency: @currency, name: "Salary", kind: :revenue)
    ImportRule.create!(user: @user, account: salary_account, match_pattern: "ACME CORP", match_type: :starts_with)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_revenue",
      amount: "3000.00",
      description: "ACME CORP PAYROLL",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal salary_account, transaction.src_account
  end

  test "expense rule matches revenue transaction for refunds" do
    sf_account, bank_account = create_linked_simplefin_account

    expense_account = Account.create!(user: @user, currency: @currency, name: "Shopping", kind: :expense)
    ImportRule.create!(user: @user, account: expense_account, match_pattern: "AMZN", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_refund",
      amount: "100.00",
      description: "AMZN REFUND",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal expense_account, transaction.src_account
    assert_equal bank_account, transaction.dest_account
  end

  test "rule with asset account creates transfer for negative transaction" do
    sf_account, bank_account = create_linked_simplefin_account

    savings_account = Account.create!(user: @user, currency: @currency, name: "Savings", kind: :asset)
    ImportRule.create!(user: @user, account: savings_account, match_pattern: "TRANSFER TO SAVINGS", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_transfer_out",
      amount: "-500.00",
      description: "TRANSFER TO SAVINGS",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do # Default expense account created before rule applied
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal bank_account, transaction.src_account
    assert_equal savings_account, transaction.dest_account
  end

  test "rule with liability account creates transfer for positive transaction" do
    sf_account, bank_account = create_linked_simplefin_account

    credit_card = Account.create!(user: @user, currency: @currency, name: "Credit Card", kind: :liability)
    ImportRule.create!(user: @user, account: credit_card, match_pattern: "CC PAYMENT", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_transfer_in",
      amount: "200.00",
      description: "CC PAYMENT RECEIVED",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do # Default revenue account created before rule applied
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal credit_card, transaction.src_account
    assert_equal bank_account, transaction.dest_account
  end

  test "rule with revenue account creates clawback for negative transaction" do
    sf_account, bank_account = create_linked_simplefin_account

    salary_account = Account.create!(user: @user, currency: @currency, name: "Salary", kind: :revenue)
    ImportRule.create!(user: @user, account: salary_account, match_pattern: "EMPLOYER", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_clawback",
      amount: "-150.00",
      description: "EMPLOYER CLAWBACK",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal bank_account, transaction.src_account
    assert_equal salary_account, transaction.dest_account
  end

  test "higher priority rule wins when multiple match" do
    sf_account, _ = create_linked_simplefin_account

    general_account = Account.create!(user: @user, currency: @currency, name: "General Shopping", kind: :expense)
    specific_account = Account.create!(user: @user, currency: @currency, name: "Amazon", kind: :expense)

    ImportRule.create!(user: @user, account: general_account, match_pattern: "AMZN", match_type: :contains, priority: 0)
    ImportRule.create!(user: @user, account: specific_account, match_pattern: "AMZN*", match_type: :starts_with, priority: 10)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_rule_priority",
      amount: "-25.00",
      description: "AMZN* Order 12345",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal specific_account, transaction.dest_account
  end

  test "auto-merges when import rule matches balance sheet account and duplicate exists" do
    sf_account_a, bank_a = create_linked_simplefin_account(remote_id: "acc_a", name: "Bank A")
    sf_account_b, bank_b = create_linked_simplefin_account(remote_id: "acc_b", name: "Bank B")

    # Import from bank_b first (no rule) — creates revenue → bank_b
    Simplefin::Transaction.create!(
      account: sf_account_b,
      remote_id: "txn_dup",
      amount: "500.00",
      description: "TRANSFER FROM A",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )
    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_b.id)

    # Create import rule mapping "TRANSFER TO B" to bank_b (asset)
    ImportRule.create!(user: @user, account: bank_b, match_pattern: "TRANSFER TO B", match_type: :contains)

    # Import from bank_a (BS rule) — creates expense first, then auto-merge finds the
    # revenue→bank_b duplicate and merges both into a bank_a→bank_b transfer
    Simplefin::Transaction.create!(
      account: sf_account_a,
      remote_id: "txn_transfer",
      amount: "-500.00",
      description: "TRANSFER TO B",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_a.id)

    # Both originals should be zeroed and merged via Transaction::Merge
    unmerged = @user.transactions.unmerged.where(amount_minor: 50000)
    assert_equal 1, unmerged.count

    merged = unmerged.first
    assert_equal bank_a, merged.src_account
    assert_equal bank_b, merged.dest_account
    assert_equal 50000, merged.amount_minor
    assert_nil merged.sourceable # Merge result has no sourceable
  end

  test "skips excluded transactions during reimport" do
    sf_account, _ = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_excluded",
      amount: "-50.00",
      description: "Excluded Transaction",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    # First import
    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction

    # Exclude it
    Transaction::Exclude.new(transaction, user: @user).call
    original_synced_at = transaction.reload.synced_at

    # Update sf transaction to simulate refresh
    travel 2.seconds
    sf_transaction.update!(synced_at: Time.current)

    # Reimport should skip excluded transaction
    assert_no_difference "Transaction.count" do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    # synced_at should not have changed
    assert_equal original_synced_at, transaction.reload.synced_at
  end

  test "exclude rule auto-excludes imported transaction" do
    sf_account, _ = create_linked_simplefin_account

    ImportRule.create!(user: @user, match_pattern: "SPAM", match_type: :contains, exclude: true)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_auto_exclude",
      amount: "-10.00",
      description: "SPAM Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert transaction.excluded?
  end

  test "adopts an orphan ledger transaction when an institution is reconnected with new IDs" do
    original_simplefin_account, ledger_account = create_linked_simplefin_account(remote_id: "acc_original", name: "Reconnected Account")

    original_simplefin_transaction = Simplefin::Transaction.create!(
      account: original_simplefin_account,
      remote_id: "txn_original",
      amount: "-50.00",
      description: "Coffee Shop",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: original_simplefin_account.id)
    original_ledger_transaction = Transaction.find_by!(sourceable: original_simplefin_transaction)
    coffee_account = original_ledger_transaction.dest_account

    # Simulate the institution being disconnected and reconnected on simplefin.org:
    # - Original Simplefin::Account stays in DB but is unlinked from the ledger account.
    # - A brand-new Simplefin::Account row appears under the same connection with a new
    #   remote_id, plus a new Simplefin::Transaction row for the same real-world transaction.
    ledger_account.update!(sourceable: nil)

    reissued_simplefin_account = Simplefin::Account.create!(
      connection: original_simplefin_account.connection,
      remote_id: "acc_reissued",
      name: original_simplefin_account.name,
      currency: original_simplefin_account.currency,
      balance: original_simplefin_account.balance
    )

    reissued_simplefin_transaction = Simplefin::Transaction.create!(
      account: reissued_simplefin_account,
      remote_id: "txn_reissued",
      amount: original_simplefin_transaction.amount,
      description: original_simplefin_transaction.description,
      posted: original_simplefin_transaction.posted,
      transacted_at: original_simplefin_transaction.transacted_at,
      pending: false
    )

    ledger_account.update!(sourceable: reissued_simplefin_account)

    assert_no_difference -> { Transaction.unmerged.where("src_account_id = :id OR dest_account_id = :id", id: ledger_account.id).count } do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: reissued_simplefin_account.id)
    end

    original_ledger_transaction.reload
    assert_equal reissued_simplefin_transaction, original_ledger_transaction.sourceable
    assert_equal coffee_account, original_ledger_transaction.dest_account
    assert_nil Transaction.where(sourceable: reissued_simplefin_transaction).where.not(id: original_ledger_transaction.id).first
  end

  test "does not adopt a same-amount-same-day transaction whose sourceable is on a still-linked aggregator account" do
    sf_account_a, ledger_a = create_linked_simplefin_account(remote_id: "acc_concurrent_a", name: "Concurrent A")
    sf_account_b, ledger_b = create_linked_simplefin_account(remote_id: "acc_concurrent_b", name: "Concurrent B")

    Simplefin::Transaction.create!(
      account: sf_account_a,
      remote_id: "txn_a",
      amount: "-25.00",
      description: "ATM Withdrawal",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )
    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_a.id)
    transactions_on_a_before = Transaction.where("src_account_id = :id OR dest_account_id = :id", id: ledger_a.id).count

    # An entirely separate, currently-linked SimpleFIN account imports a transaction with
    # the same amount, day, and description. It must NOT adopt the existing ledger row on
    # ledger_a — that row's sourceable is on a still-linked account.
    sf_transaction_b = Simplefin::Transaction.create!(
      account: sf_account_b,
      remote_id: "txn_b",
      amount: "-25.00",
      description: "ATM Withdrawal",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_b.id)

    # The new import lands on ledger_b as expected, leaving ledger_a's transaction untouched.
    new_ledger_transaction = Transaction.find_by(sourceable: sf_transaction_b)
    assert_not_nil new_ledger_transaction
    assert_includes [ new_ledger_transaction.src_account, new_ledger_transaction.dest_account ], ledger_b
    assert_equal transactions_on_a_before, Transaction.where("src_account_id = :id OR dest_account_id = :id", id: ledger_a.id).count
  end

  test "falls back to exact name match when no rule matches" do
    sf_account, _ = create_linked_simplefin_account

    ImportRule.create!(user: @user, account: accounts(:expense_account), match_pattern: "NOMATCH", match_type: :exact)

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_no_rule",
      amount: "-30.00",
      description: "Random Store",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal "Random Store", transaction.dest_account.name
  end

  test "aggregates sidebar broadcasts to one per affected account regardless of row count" do
    sf_account, bank_account = create_linked_simplefin_account

    expense_account = Account.create!(user: @user, currency: @currency, name: "Coffee", kind: :expense)

    3.times do |i|
      Simplefin::Transaction.create!(
        account: sf_account,
        remote_id: "txn_agg_#{i}",
        amount: "-#{i + 1}.00",
        description: "Coffee",
        posted: i.days.ago,
        transacted_at: i.days.ago,
        pending: false
      )
    end

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    targets = streams.select { |s| s["action"] == "update" }.map { |s| s["target"] }.sort
    expected = [
      ActionView::RecordIdentifier.dom_id(bank_account, :sidebar_link),
      ActionView::RecordIdentifier.dom_id(expense_account, :sidebar_link)
    ].sort
    assert_equal expected, targets
  end

  test "broadcasts nothing when there are no aggregator transactions to import" do
    sf_account, _ = create_linked_simplefin_account

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account.id)
    end

    assert_empty streams
  end

  test "auto-merge broadcasts include counterparty accounts from merged candidates" do
    sf_account_a, bank_a = create_linked_simplefin_account(remote_id: "acc_broadcast_a", name: "Bank A")
    sf_account_b, bank_b = create_linked_simplefin_account(remote_id: "acc_broadcast_b", name: "Bank B")

    # First import from bank_b: creates a revenue -> bank_b transaction; revenue account is
    # auto-created here and will be affected again when Merge zeroes out the candidate.
    Simplefin::Transaction.create!(
      account: sf_account_b,
      remote_id: "broadcast_dup",
      amount: "500.00",
      description: "TRANSFER FROM A",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )
    Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_b.id)
    revenue_counterparty = @user.accounts.find_by!(name: "TRANSFER FROM A", kind: :revenue)

    # Rule maps TRANSFER TO B -> bank_b, so auto-merge kicks in on the bank_a import.
    ImportRule.create!(user: @user, account: bank_b, match_pattern: "TRANSFER TO B", match_type: :contains)

    Simplefin::Transaction.create!(
      account: sf_account_a,
      remote_id: "broadcast_transfer",
      amount: "-500.00",
      description: "TRANSFER TO B",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    streams = capture_turbo_stream_broadcasts([ @user, :sidebar ]) do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: sf_account_a.id)
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

    def create_linked_simplefin_account(remote_id: "acc_test", name: "SF Test Checking")
      sf_account = Simplefin::Account.create!(
        connection: simplefin_connections(:one),
        remote_id: remote_id,
        name: name,
        currency: "USD",
        balance: "1000.00"
      )

      bank_account = Account.create!(
        user: @user,
        currency: @currency,
        name: "Linked #{name}",
        kind: :asset,
        sourceable: sf_account
      )

      [ sf_account, bank_account ]
    end
end
