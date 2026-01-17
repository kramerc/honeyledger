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
end
