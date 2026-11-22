module CurrenciesHelper
  def amount_to_currency(amount_minor, currency)
    number_to_currency(BigDecimal(amount_minor) / (10 ** currency.decimal_places), unit: currency.symbol, precision: currency.decimal_places)
  end

  def amount_minor_to_decimal(amount_minor, currency)
    decimal_value = BigDecimal(amount_minor) / (10 ** currency.decimal_places)
    # number_with_precision rounds the BigDecimal itself; format("%f") would go through a Float.
    number_with_precision(decimal_value, precision: currency.decimal_places, delimiter: "")
  end
end
