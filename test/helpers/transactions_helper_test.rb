require "test_helper"

class TransactionsHelperTest < ActionView::TestCase
  include CurrenciesHelper

  test "transaction_amount_with_currency formats amount with currency" do
    transaction = Transaction.new(amount_minor: 1500, currency: currencies(:usd))

    result = transaction_amount_with_currency(transaction)

    assert_equal "$15.00", result
  end

  test "transaction_fx_amount_with_currency formats FX amount when present" do
    transaction = Transaction.new(
      fx_amount_minor: 2000,
      fx_currency: currencies(:eur)
    )
    transaction.define_singleton_method(:has_fx?) { true }

    result = transaction_fx_amount_with_currency(transaction)

    assert_equal "€20.00", result
  end

  test "transaction_fx_amount_with_currency returns nil when no FX data" do
    transaction = Transaction.new
    transaction.define_singleton_method(:has_fx?) { false }

    result = transaction_fx_amount_with_currency(transaction)

    assert_nil result
  end

  test "transaction_amount_with_currency with JPY currency" do
    transaction = Transaction.new(amount_minor: 1500, currency: currencies(:jpy))

    result = transaction_amount_with_currency(transaction)

    assert_equal "¥1,500", result
  end

  test "transaction_amount_with_currency with crypto" do
    transaction = Transaction.new(amount_minor: 100000000, currency: currencies(:btc))

    result = transaction_amount_with_currency(transaction)

    assert_equal "₿1.00000000", result
  end

  test "account_options_with_kind includes data attributes" do
    accounts = [
      accounts(:asset_account),
      accounts(:expense_account)
    ]

    result = account_options_with_kind(accounts, accounts(:asset_account).id)

    assert_match /data-kind="asset"/, result
    assert_match /data-currency="USD"/, result
    assert_match /selected/, result
  end

  test "account_options_with_kind with prompt" do
    accounts = [ accounts(:asset_account) ]

    result = account_options_with_kind(accounts, nil, prompt: "Select account")

    assert_match /Select account/, result
    assert_match /value=""/, result
  end
end
