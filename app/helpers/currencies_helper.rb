module CurrenciesHelper
  def amount_to_currency(amount_minor, currency)
    number_to_currency(amount_minor.to_f / (10 ** currency.decimal_places), unit: currency.symbol, precision: currency.decimal_places)
  end

  def amount_minor_to_decimal(amount_minor, currency)
    decimal_value = BigDecimal(amount_minor) / (10 ** currency.decimal_places)
    format("%.#{currency.decimal_places}f", decimal_value)
  end
end
