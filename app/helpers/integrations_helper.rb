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

  # The currency code an aggregator reported for one of its accounts. A blank
  # code is flagged rather than left empty, because it is what makes
  # `aggregator_balance` fall back to a bare number with no currency symbol.
  def aggregator_currency(aggregator_account)
    return aggregator_account.currency if aggregator_account.currency.present?

    tag.span "(missing)", class: "marker",
      title: "The aggregator did not report a currency for this account, so its balance is shown without a currency symbol."
  end
end
