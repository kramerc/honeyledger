module CurrenciesHelper
  def amount_to_currency(amount_minor, currency)
    number_to_currency(amount_minor.to_f / (10 ** currency.decimal_places), unit: currency.symbol, precision: currency.decimal_places)
  end
end
