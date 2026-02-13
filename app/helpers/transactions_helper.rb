module TransactionsHelper
  def transaction_type_indicator(transaction)
    return "" if transaction.dest_account.nil? || transaction.src_account.nil?

    if transaction.dest_account.expense?
      tag.span("↓ Withdrawal", style: "color: red;")
    elsif transaction.src_account.revenue?
      tag.span("↑ Deposit", style: "color: green;")
    else
      tag.span("⇄ Transfer", style: "color: gray;")
    end
  end

  def transaction_amount_with_currency(transaction)
    amount_to_currency(transaction.amount_minor, transaction.currency)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end
end
