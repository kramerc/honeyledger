module TransactionsHelper
  def transaction_type_indicator(transaction, **html_options)
    return tag.span("", **html_options) if transaction.dest_account.nil? || transaction.src_account.nil?

    if transaction.dest_account.expense?
      tag.span("↓ Withdrawal", **{ class: "tx-type tx-type--withdrawal" }.merge(html_options))
    elsif transaction.src_account.revenue?
      tag.span("↑ Deposit", **{ class: "tx-type tx-type--deposit" }.merge(html_options))
    else
      tag.span("⇄ Transfer", **{ class: "tx-type tx-type--transfer" }.merge(html_options))
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
