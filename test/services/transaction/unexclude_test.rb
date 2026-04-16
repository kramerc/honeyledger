require "test_helper"

class Transaction::UnexcludeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank = accounts(:linked_asset)
    @expense = Account.create!(user: @user, name: "Unexclude Expense", kind: :expense, currency: @currency)

    @transaction = Transaction.create!(
      user: @user,
      src_account: @bank,
      dest_account: @expense,
      amount_minor: 1000,
      currency: @currency,
      description: "Test unexclude",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_one)
    )

    Transaction::Exclude.new(@transaction, user: @user).call
    @transaction.reload
  end

  test "unexcludes a transaction" do
    unexcluder = Transaction::Unexclude.new(@transaction, user: @user)
    assert unexcluder.call

    @transaction.reload
    assert_not @transaction.excluded?
    assert_nil @transaction.excluded_at
    assert_equal 1000, @transaction.amount_minor
  end

  test "re-applies account balances on unexclude" do
    @bank.reset_balance
    @expense.reset_balance
    bank_before = @bank.reload.balance_minor
    expense_before = @expense.reload.balance_minor

    Transaction::Unexclude.new(@transaction, user: @user).call

    @bank.reload
    @expense.reload
    assert_equal bank_before - 1000, @bank.balance_minor
    assert_equal expense_before + 1000, @expense.balance_minor
  end

  test "unexcluded transaction appears in unexcluded scope" do
    Transaction::Unexclude.new(@transaction, user: @user).call

    assert_includes @user.transactions.unexcluded, @transaction.reload
    assert_not_includes @user.transactions.excluded, @transaction
  end

  test "rejects non-excluded transaction" do
    plain = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense,
      amount_minor: 500, currency: @currency, description: "Plain",
      transacted_at: Time.current
    )

    unexcluder = Transaction::Unexclude.new(plain, user: @user)
    assert_not unexcluder.call
    assert_includes unexcluder.errors, "Transaction is not excluded"
  end

  test "rejects other user's transaction" do
    other_user = users(:two)
    unexcluder = Transaction::Unexclude.new(@transaction, user: other_user)
    assert_not unexcluder.call
    assert_includes unexcluder.errors, "Transaction must belong to you"
  end

  test "returns false with error when RecordInvalid is raised" do
    @transaction.update_columns(src_account_id: @transaction.dest_account_id)

    unexcluder = Transaction::Unexclude.new(@transaction.reload, user: @user)
    assert_not unexcluder.call
    assert unexcluder.errors.any?
  end

  test "handles FX transaction unexclusion" do
    # Create a fresh FX transaction and exclude it
    eur = currencies(:eur)
    fx_transaction = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense,
      amount_minor: 1000, fx_amount_minor: 900, fx_currency: eur,
      currency: @currency, description: "FX unexclude",
      transacted_at: 1.day.ago
    )

    Transaction::Exclude.new(fx_transaction, user: @user).call
    fx_transaction.reload

    @bank.reset_balance
    bank_before = @bank.reload.balance_minor

    Transaction::Unexclude.new(fx_transaction, user: @user).call

    @bank.reload
    # Src side uses fx_amount_minor
    assert_equal bank_before - 900, @bank.balance_minor
  end
end
