require "test_helper"

class CurrenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @currency = currencies(:usd)
  end

  test "should get index" do
    get currencies_url
    assert_response :success
  end

  test "should get new" do
    get new_currency_url
    assert_response :success
  end

  test "should create currency" do
    assert_difference("Currency.count") do
      post currencies_url, params: { currency: { name: "British Pound", kind: "fiat", symbol: "£", code: "GBP", decimal_places: 2, active: true } }
    end

    assert_redirected_to currency_url(Currency.last)
  end

  test "should show currency" do
    get currency_url(@currency)
    assert_response :success
  end

  test "should get edit" do
    get edit_currency_url(@currency)
    assert_response :success
  end

  test "should update currency" do
    patch currency_url(@currency), params: { currency: { name: @currency.name, kind: @currency.kind, symbol: @currency.symbol, code: @currency.code, decimal_places: @currency.decimal_places, active: @currency.active } }
    assert_redirected_to currency_url(@currency)
  end

  test "should destroy currency" do
    # Create a currency that's not used by any accounts or transactions
    unused_currency = Currency.create!(
      name: "Test Currency",
      kind: "fiat",
      symbol: "TC",
      code: "TST",
      decimal_places: 2,
      active: false
    )

    assert_difference("Currency.count", -1) do
      delete currency_url(unused_currency)
    end

    assert_redirected_to currencies_url
  end
end
