require "test_helper"

class TransactionImportJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)

    # Clear any aggregator transactions that would be imported from fixtures (linked via Account.sourceable)
    linked_sf_ids = Account.where(sourceable_type: "Simplefin::Account").where.not(sourceable_id: nil).pluck(:sourceable_id)
    Simplefin::Transaction.where(account_id: linked_sf_ids).destroy_all

    linked_lf_ids = Account.where(sourceable_type: "Lunchflow::Account").where.not(sourceable_id: nil).pluck(:sourceable_id)
    Lunchflow::Transaction.where(account_id: linked_lf_ids).destroy_all

    # Set up SimpleFIN test data
    @simplefin_connection = simplefin_connections(:one)

    @simplefin_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_test",
      name: "Test Checking",
      currency: "USD",
      balance: "1000.00"
    )

    # Create a bank account linked to SimpleFIN (FK is on Account side)
    @bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Checking Account",
      kind: :asset,
      sourceable: @simplefin_account
    )
  end

  # SimpleFIN import tests

  test "imports expense transaction (negative amount)" do
    # Create a SimpleFIN transaction with negative amount (money out)
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_expense_1",
      amount: "-50.00",
      description: "Coffee Shop",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        # Creates expense account
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal @bank_account, transaction.src_account
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
    # Create a SimpleFIN transaction with positive amount (money in)
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_revenue_1",
      amount: "2500.00",
      description: "Salary Payment",
      posted: 3.days.ago,
      transacted_at: 3.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        # Creates revenue account
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal @bank_account, transaction.dest_account
    assert_equal "Salary Payment", transaction.src_account.name
    assert_equal "revenue", transaction.src_account.kind
    assert_equal "Salary Payment", transaction.description
    assert_equal 250000, transaction.amount_minor
    assert_equal @currency, transaction.currency
  end

  test "reuses existing expense account with same name" do
    # Pre-create an expense account
    expense_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Grocery Store",
      kind: :expense
    )

    # Create two transactions with the same description
    sf_transaction1 = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_1",
      amount: "-100.00",
      description: "Grocery Store",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    sf_transaction2 = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_2",
      amount: "-150.00",
      description: "Grocery Store",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 2 do
      assert_no_difference "Account.count" do
        # Reuses existing account
        TransactionImportJob.perform_now
      end
    end

    transaction1 = Transaction.find_by(sourceable: sf_transaction1)
    transaction2 = Transaction.find_by(sourceable: sf_transaction2)

    assert_equal expense_account, transaction1.dest_account
    assert_equal expense_account, transaction2.dest_account
  end

  test "updates existing transaction when SimpleFIN transaction is updated" do
    # Create and import a transaction
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_update",
      amount: "-75.00",
      description: "Original Description",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    TransactionImportJob.perform_now

    transaction = Transaction.find_by(sourceable: sf_transaction)
    original_synced_at = transaction.synced_at

    # Wait a moment and update the SimpleFIN transaction with a new synced_at
    travel 2.seconds

    sf_transaction.update!(
      amount: "-85.00",
      synced_at: Time.current
    )

    assert_no_difference "Transaction.count" do
      assert_no_difference "Account.count" do
        TransactionImportJob.perform_now
      end
    end

    transaction.reload
    assert_equal 8500, transaction.amount_minor
    assert transaction.synced_at > original_synced_at
  end

  test "skips transactions without linked account" do
    # Create a SimpleFIN account without a linked ledger account
    unlinked_sf_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
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
      TransactionImportJob.perform_now
    end
  end

  test "handles transaction without posted date" do
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_no_posted",
      amount: "-30.00",
      description: "No Posted Date",
      posted: nil,
      transacted_at: Time.current,
      pending: true
    )

    assert_difference "Transaction.count", 1 do
      TransactionImportJob.perform_now
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_not_nil transaction
    assert_not_nil transaction.transacted_at
    assert_nil transaction.cleared_at # No cleared_at when posted is nil
  end

  test "sanitizes long account names" do
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_long_name",
      amount: "-20.00",
      description: "A" * 100, # Very long description
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    expense_account = transaction.dest_account

    assert expense_account.name.length <= 50
    assert_equal "A" * 47 + "...", expense_account.name
  end

  test "sanitizes account names with extra whitespace" do
    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_whitespace",
      amount: "-15.00",
      description: "  Multiple   Spaces   Store  ",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    expense_account = transaction.dest_account

    assert_equal "Multiple Spaces Store", expense_account.name
  end

  test "only imports transactions that are new or updated since last sync" do
    # Create an already-synced transaction
    _sf_transaction_old = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_old",
      amount: "-50.00",
      description: "Old Transaction",
      posted: 5.days.ago,
      transacted_at: 5.days.ago,
      pending: false
    )

    # Import it
    TransactionImportJob.perform_now

    # Create a new transaction
    sf_transaction_new = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_new",
      amount: "-30.00",
      description: "New Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    # Run job again - should only import the new one
    assert_difference "Transaction.count", 1 do
      TransactionImportJob.perform_now
    end

    # Verify the new transaction was created
    assert_not_nil Transaction.find_by(sourceable: sf_transaction_new)
  end

  test "imports only transactions for specified simplefin_account_id" do
    # Create a second SimpleFIN account linked to a bank account
    second_simplefin_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_test_2",
      name: "Test Savings",
      currency: "USD",
      balance: "5000.00"
    )

    Account.create!(
      user: @user,
      currency: @currency,
      name: "Savings Account",
      kind: :asset,
      sourceable: second_simplefin_account
    )

    # Create transactions in both accounts
    sf_transaction_first = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_first_account",
      amount: "-50.00",
      description: "First Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    sf_transaction_second = Simplefin::Transaction.create!(
      account: second_simplefin_account,
      remote_id: "txn_second_account",
      amount: "-75.00",
      description: "Second Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    # Import only transactions from the first account
    assert_difference "Transaction.count", 1 do
      TransactionImportJob.perform_now(simplefin_account_id: @simplefin_account.id)
    end

    # Verify only the first account's transaction was imported
    assert_not_nil Transaction.find_by(sourceable: sf_transaction_first)
    assert_nil Transaction.find_by(sourceable: sf_transaction_second)
  end

  test "imports all transactions when simplefin_account_id is not specified" do
    # Create a second SimpleFIN account linked to a bank account
    second_simplefin_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_test_3",
      name: "Test Savings",
      currency: "USD",
      balance: "5000.00"
    )

    Account.create!(
      user: @user,
      currency: @currency,
      name: "Savings Account",
      kind: :asset,
      sourceable: second_simplefin_account
    )

    # Create transactions in both accounts
    sf_transaction_first = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_all_first",
      amount: "-50.00",
      description: "First Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    sf_transaction_second = Simplefin::Transaction.create!(
      account: second_simplefin_account,
      remote_id: "txn_all_second",
      amount: "-75.00",
      description: "Second Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    # Import all transactions (no simplefin_account_id specified)
    assert_difference "Transaction.count", 2 do
      TransactionImportJob.perform_now
    end

    # Verify both transactions were imported
    assert_not_nil Transaction.find_by(sourceable: sf_transaction_first)
    assert_not_nil Transaction.find_by(sourceable: sf_transaction_second)
  end

  test "simplefin_account_id filter respects other scoping rules" do
    # Create a second SimpleFIN account that is NOT linked to a ledger account
    unlinked_simplefin_account = Simplefin::Account.create!(
      connection: @simplefin_connection,
      remote_id: "acc_unlinked_filter",
      name: "Unlinked Account",
      currency: "USD",
      balance: "3000.00"
    )

    # Create transaction in unlinked account
    _sf_transaction_unlinked = Simplefin::Transaction.create!(
      account: unlinked_simplefin_account,
      remote_id: "txn_unlinked_filter",
      amount: "-25.00",
      description: "Should Be Skipped",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    # Try to import with specific account_id - should still skip because account not linked
    assert_no_difference "Transaction.count" do
      TransactionImportJob.perform_now(simplefin_account_id: unlinked_simplefin_account.id)
    end
  end

  test "uses account rule to route expense transaction" do
    grocery_account = Account.create!(user: @user, currency: @currency, name: "Groceries", kind: :expense)
    ImportRule.create!(user: @user, account: grocery_account, match_pattern: "WHOLEFDS", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_rule_expense",
      amount: "-45.00",
      description: "WHOLEFDS MKT #10234",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal grocery_account, transaction.dest_account
  end

  test "uses account rule to route revenue transaction" do
    salary_account = Account.create!(user: @user, currency: @currency, name: "Salary", kind: :revenue)
    ImportRule.create!(user: @user, account: salary_account, match_pattern: "ACME CORP", match_type: :starts_with)

    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_rule_revenue",
      amount: "3000.00",
      description: "ACME CORP PAYROLL",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_no_difference "Account.count" do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal salary_account, transaction.src_account
  end

  test "expense rule does not match revenue transaction" do
    expense_account = Account.create!(user: @user, currency: @currency, name: "Shopping", kind: :expense)
    ImportRule.create!(user: @user, account: expense_account, match_pattern: "AMZN", match_type: :contains)

    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_rule_wrong_kind",
      amount: "100.00",
      description: "AMZN REFUND",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal "revenue", transaction.src_account.kind
    assert_not_equal expense_account, transaction.src_account
  end

  test "higher priority rule wins when multiple match" do
    general_account = Account.create!(user: @user, currency: @currency, name: "General Shopping", kind: :expense)
    specific_account = Account.create!(user: @user, currency: @currency, name: "Amazon", kind: :expense)

    ImportRule.create!(user: @user, account: general_account, match_pattern: "AMZN", match_type: :contains, priority: 0)
    ImportRule.create!(user: @user, account: specific_account, match_pattern: "AMZN*", match_type: :starts_with, priority: 10)

    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_rule_priority",
      amount: "-25.00",
      description: "AMZN* Order 12345",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    TransactionImportJob.perform_now

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal specific_account, transaction.dest_account
  end

  test "falls back to exact name match when no rule matches" do
    ImportRule.create!(user: @user, account: accounts(:expense_account), match_pattern: "NOMATCH", match_type: :exact)

    sf_transaction = Simplefin::Transaction.create!(
      account: @simplefin_account,
      remote_id: "txn_no_rule",
      amount: "-30.00",
      description: "Random Store",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do
        TransactionImportJob.perform_now
      end
    end

    transaction = Transaction.find_by(sourceable: sf_transaction)
    assert_equal "Random Store", transaction.dest_account.name
  end

  # Lunch Flow import tests

  test "imports lunchflow expense transaction (negative amount)" do
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
      TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)
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

  test "imports lunchflow revenue transaction (positive amount)" do
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
      TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)
    end

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_not_nil transaction
    assert_equal @user, transaction.user
    assert_equal lf_bank_account, transaction.dest_account
    assert_equal "Salary", transaction.description
    assert_equal "revenue", transaction.src_account.kind
    assert_equal 250000, transaction.amount_minor
  end

  test "lunchflow import uses merchant over description" do
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

    TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_equal "Whole Foods", transaction.description
  end

  test "lunchflow pending transaction has nil cleared_at" do
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

    TransactionImportJob.perform_now(lunchflow_account_id: lf_account.id)

    transaction = Transaction.find_by(sourceable: lf_transaction)
    assert_nil transaction.cleared_at
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
        name: "LF #{name}",
        kind: :asset,
        sourceable: lf_account
      )

      [ lf_account, lf_bank_account ]
    end
end
