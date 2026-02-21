require "test_helper"
require "ostruct"

class CurrenciesHelperTest < ActionView::TestCase
  test "amount_to_currency formats amount with 2 decimal places" do
    currency = currencies(:usd)

    result = amount_to_currency(1500, currency)

    assert_equal "$15.00", result
  end

  test "amount_to_currency formats amount with 0 decimal places" do
    currency = currencies(:jpy)

    result = amount_to_currency(1500, currency)

    assert_equal "¥1,500", result
  end

  test "amount_to_currency formats amount with 8 decimal places for crypto" do
    currency = currencies(:btc)

    result = amount_to_currency(100000000, currency)

    assert_equal "₿1.00000000", result
  end

  test "amount_to_currency handles zero amount" do
    currency = currencies(:usd)

    result = amount_to_currency(0, currency)

    assert_equal "$0.00", result
  end

  test "amount_to_currency handles negative amount" do
    currency = currencies(:usd)

    result = amount_to_currency(-1500, currency)

    assert_equal "-$15.00", result
  end

  test "amount_to_currency handles large amounts" do
    currency = currencies(:usd)

    result = amount_to_currency(123456789, currency)

    assert_equal "$1,234,567.89", result
  end

  test "amount_to_currency converts minor units correctly" do
    currency = OpenStruct.new(symbol: "€", decimal_places: 2)

    result = amount_to_currency(2550, currency)

    assert_equal "€25.50", result
  end

  test "amount_to_currency handles 4 decimal place currencies" do
    currency = OpenStruct.new(symbol: "KWD", decimal_places: 4)

    result = amount_to_currency(12345, currency)

    assert_equal "KWD1.2345", result
  end

  test "amount_minor_to_decimal formats with 2 decimal places" do
    currency = currencies(:usd)

    result = amount_minor_to_decimal(1500, currency)

    assert_equal "15.00", result
  end

  test "amount_minor_to_decimal formats with 0 decimal places" do
    currency = currencies(:jpy)

    result = amount_minor_to_decimal(1500, currency)

    assert_equal "1500", result
  end

  test "amount_minor_to_decimal formats with 8 decimal places" do
    currency = currencies(:btc)

    result = amount_minor_to_decimal(100000000, currency)

    assert_equal "1.00000000", result
  end
end
