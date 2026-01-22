require "test_helper"

class TransactionImportJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)

    # Clear any SimpleFin transactions that would be imported from fixtures
    SimplefinTransaction.where(simplefin_account: SimplefinAccount.where.not(account_id: nil)).destroy_all

    # Create a bank account linked to SimpleFin
    @bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Checking Account",
      kind: :asset
    )

    # Use existing SimpleFin connection from fixtures
    @simplefin_connection = simplefin_connections(:one)

    @simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: @bank_account,
      remote_id: "acc_test",
      name: "Test Checking",
      currency: "USD",
      balance: "1000.00"
    )
  end

  test "imports expense transaction (negative amount)" do
    # Create a SimpleFin transaction with negative amount (money out)
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_expense_1",
      amount: "-50.00",
      description: "Coffee Shop",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do  # Creates expense account
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
    assert_equal 5000, transaction.amount_minor  # Absolute value
    assert_equal @currency, transaction.currency
    assert_not_nil transaction.transacted_at
    assert_not_nil transaction.cleared_at
    assert_not_nil transaction.synced_at
  end

  test "imports revenue transaction (positive amount)" do
    # Create a SimpleFin transaction with positive amount (money in)
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_revenue_1",
      amount: "2500.00",
      description: "Salary Payment",
      posted: 3.days.ago,
      transacted_at: 3.days.ago,
      pending: false
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do  # Creates revenue account
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
    sf_transaction1 = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_1",
      amount: "-100.00",
      description: "Grocery Store",
      posted: 2.days.ago,
      transacted_at: 2.days.ago,
      pending: false
    )

    sf_transaction2 = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_2",
      amount: "-150.00",
      description: "Grocery Store",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    assert_difference "Transaction.count", 2 do
      assert_no_difference "Account.count" do  # Reuses existing account
        TransactionImportJob.perform_now
      end
    end

    transaction1 = Transaction.find_by(sourceable: sf_transaction1)
    transaction2 = Transaction.find_by(sourceable: sf_transaction2)

    assert_equal expense_account, transaction1.dest_account
    assert_equal expense_account, transaction2.dest_account
  end

  test "updates existing transaction when SimpleFin transaction is updated" do
    # Create and import a transaction
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
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

    # Wait a moment and update the SimpleFin transaction with a new synced_at
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
    # Create a SimpleFin account without a linked ledger account
    unlinked_sf_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: nil,  # No linked account
      remote_id: "acc_unlinked",
      name: "Unlinked Account",
      currency: "USD",
      balance: "500.00"
    )

    _sf_transaction = SimplefinTransaction.create!(
      simplefin_account: unlinked_sf_account,
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
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
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
    assert_nil transaction.cleared_at  # No cleared_at when posted is nil
  end

  test "sanitizes long account names" do
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_long_name",
      amount: "-20.00",
      description: "A" * 100,  # Very long description
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
    sf_transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
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
    _sf_transaction_old = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
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
    sf_transaction_new = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
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
    # Create a second SimpleFin account
    second_bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Savings Account",
      kind: :asset
    )

    second_simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: second_bank_account,
      remote_id: "acc_test_2",
      name: "Test Savings",
      currency: "USD",
      balance: "5000.00"
    )

    # Create transactions in both accounts
    sf_transaction_first = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_first_account",
      amount: "-50.00",
      description: "First Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    sf_transaction_second = SimplefinTransaction.create!(
      simplefin_account: second_simplefin_account,
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
    # Create a second SimpleFin account
    second_bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Savings Account",
      kind: :asset
    )

    second_simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: second_bank_account,
      remote_id: "acc_test_3",
      name: "Test Savings",
      currency: "USD",
      balance: "5000.00"
    )

    # Create transactions in both accounts
    sf_transaction_first = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_all_first",
      amount: "-50.00",
      description: "First Account Transaction",
      posted: 1.day.ago,
      transacted_at: 1.day.ago,
      pending: false
    )

    sf_transaction_second = SimplefinTransaction.create!(
      simplefin_account: second_simplefin_account,
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
    # Create a second SimpleFin account that is NOT linked to a ledger account
    unlinked_simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: nil,  # Not linked
      remote_id: "acc_unlinked_filter",
      name: "Unlinked Account",
      currency: "USD",
      balance: "3000.00"
    )

    # Create transaction in unlinked account
    _sf_transaction_unlinked = SimplefinTransaction.create!(
      simplefin_account: unlinked_simplefin_account,
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
end
