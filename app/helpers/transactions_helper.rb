module TransactionsHelper
  def transaction_type_indicator(transaction, **html_options)
    return tag.span("", **html_options) if transaction.dest_account.nil? || transaction.src_account.nil?

    if transaction.dest_account.expense?
      options = html_options.merge(class: class_names("tx-type tx-type--withdrawal", html_options[:class]))
      tag.span("↓ Withdrawal", **options)
    elsif transaction.src_account.revenue?
      options = html_options.merge(class: class_names("tx-type tx-type--deposit", html_options[:class]))
      tag.span("↑ Deposit", **options)
    else
      options = html_options.merge(class: class_names("tx-type tx-type--transfer", html_options[:class]))
      tag.span("⇄ Transfer", **options)
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
