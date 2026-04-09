require "test_helper"

class Transaction::ExcludeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank = accounts(:linked_asset)
    @expense = Account.create!(user: @user, name: "Exclude Expense", kind: :expense, currency: @currency)

    @transaction = Transaction.create!(
      user: @user,
      src_account: @bank,
      dest_account: @expense,
      amount_minor: 1000,
      currency: @currency,
      description: "Test exclusion",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_one)
    )
  end

  test "excludes a transaction" do
    excluder = Transaction::Exclude.new(@transaction, user: @user)
    assert excluder.call

    @transaction.reload
    assert @transaction.excluded?
    assert_not_nil @transaction.excluded_at
    assert_equal 1000, @transaction.amount_minor # amounts unchanged
  end

  test "reverses account balances on exclude" do
    @bank.reset_balance
    @expense.reset_balance
    bank_before = @bank.reload.balance_minor
    expense_before = @expense.reload.balance_minor

    excluder = Transaction::Exclude.new(@transaction, user: @user)
    excluder.call

    @bank.reload
    @expense.reload
    assert_equal bank_before + 1000, @bank.balance_minor
    assert_equal expense_before - 1000, @expense.balance_minor
  end

  test "excluded transactions are filtered from unexcluded scope" do
    Transaction::Exclude.new(@transaction, user: @user).call

    assert_not_includes @user.transactions.unexcluded, @transaction.reload
    assert_includes @user.transactions.excluded, @transaction
  end

  test "rejects already excluded transaction" do
    Transaction::Exclude.new(@transaction, user: @user).call

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert_not excluder.call
    assert_includes excluder.errors, "Transaction is already excluded"
  end

  test "rejects merged transaction" do
    @transaction.update_columns(merged_into_id: @transaction.id)

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert_not excluder.call
    assert_includes excluder.errors, "Merged transactions cannot be excluded"
  end

  test "rejects opening balance transaction" do
    @transaction.update_columns(opening_balance: true)

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert_not excluder.call
    assert_includes excluder.errors, "Opening balance transactions cannot be excluded"
  end

  test "rejects split transactions" do
    @transaction.update_columns(split: true)

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert_not excluder.call
    assert_includes excluder.errors, "Split transactions cannot be excluded"
  end

  test "rejects other user's transaction" do
    other_user = users(:two)
    excluder = Transaction::Exclude.new(@transaction, user: other_user)
    assert_not excluder.call
    assert_includes excluder.errors, "Transaction must belong to you"
  end

  test "rejects transaction with merged sources" do
    # Create a merged transaction scenario
    revenue = Account.create!(user: @user, name: "Exclude Revenue", kind: :revenue, currency: @currency)
    bank_b = accounts(:asset_account)

    deposit = Transaction.create!(
      user: @user, src_account: revenue, dest_account: bank_b,
      amount_minor: 1000, currency: @currency, description: "Deposit",
      transacted_at: 1.day.ago
    )

    merger = Transaction::Merge.new(@transaction, deposit, user: @user)
    merger.call
    merged = merger.merged_transaction

    excluder = Transaction::Exclude.new(merged, user: @user)
    assert_not excluder.call
    assert_includes excluder.errors, "Merged transfer transactions cannot be excluded"
  end

  test "returns false with error when RecordInvalid is raised" do
    @transaction.update_columns(src_account_id: @transaction.dest_account_id)

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert_not excluder.call
    assert excluder.errors.any?
  end

  test "handles FX transaction exclusion" do
    eur = currencies(:eur)
    @transaction.update!(fx_amount_minor: 900, fx_currency: eur)

    @bank.reset_balance
    bank_before = @bank.reload.balance_minor

    excluder = Transaction::Exclude.new(@transaction.reload, user: @user)
    assert excluder.call

    @bank.reload
    # Src side uses fx_amount_minor
    assert_equal bank_before + 900, @bank.balance_minor
  end
end
