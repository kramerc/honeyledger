module TransactionsHelper
  def transaction_amount_with_currency(transaction)
    amount_to_currency(transaction.amount_minor, transaction.currency)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end
end
