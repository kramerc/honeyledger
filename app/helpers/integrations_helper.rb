module IntegrationsHelper
  # Formats the balance an aggregator reported for one of its accounts, in the
  # currency the aggregator reported it in. That can differ from the linked
  # ledger account's currency, so this deliberately avoids `ledger_currency` and
  # `balance_minor`. Falls back to the raw value and currency code when the
  # reported currency is not registered in the app.
  def aggregator_balance(aggregator_account)
    return "—" if aggregator_account.balance.blank?

    currency = Currency.find_by(code: aggregator_account.currency)
    if currency
      amount_to_currency(Minorable::Helpers.minor_from(aggregator_account.balance, currency.decimal_places), currency)
    else
      "#{aggregator_account.balance} #{aggregator_account.currency}".strip
    end
  end
end
