module CurrenciesHelper
  def amount_to_currency(amount_minor, currency)
    number_to_currency(amount_minor.to_f / (10 ** currency.decimal_places), unit: currency.symbol, precision: currency.decimal_places)
  end

  def amount_minor_to_decimal(amount_minor, currency)
    format("%.#{currency.decimal_places}f", amount_minor.to_f / (10 ** currency.decimal_places))
  end
end
