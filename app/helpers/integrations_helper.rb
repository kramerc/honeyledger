module IntegrationsHelper
  # Formats the balance an aggregator reported for one of its accounts. Falls back
  # to the raw value and currency code when the aggregator's currency is not
  # registered in the app, so an unknown currency still shows something.
  def aggregator_balance(aggregator_account)
    return "—" if aggregator_account.balance.blank?

    currency = aggregator_account.ledger_currency
    if currency
      amount_to_currency(aggregator_account.balance_minor, currency)
    else
      "#{aggregator_account.balance} #{aggregator_account.currency}".strip
    end
  end
end
