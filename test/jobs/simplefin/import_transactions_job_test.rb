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

  test "sanitizes long account names" do
    sf_account, _ = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_long_name",
      amount: "-20.00",
      description: "A" * 100,
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
    expense_account = transaction.dest_account

    assert expense_account.name.length <= 50
    assert_equal "A" * 47 + "...", expense_account.name
  end

  test "sanitizes account names with extra whitespace" do
    sf_account, _ = create_linked_simplefin_account

    sf_transaction = Simplefin::Transaction.create!(
      account: sf_account,
      remote_id: "txn_whitespace",
      amount: "-15.00",
      description: "  Multiple   Spaces   Store  ",
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
    expense_account = transaction.dest_account

    assert_equal "Multiple Spaces Store", expense_account.name
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
      assert_no_difference "Account.count" do
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
      assert_no_difference "Account.count" do
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
