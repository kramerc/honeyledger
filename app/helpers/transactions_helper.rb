module TransactionsHelper
  def transaction_type_indicator(transaction, **html_options)
    return tag.span("", **html_options) if transaction.dest_account.nil? || transaction.src_account.nil?

    src_kind = transaction.src_account.kind
    dest_kind = transaction.dest_account.kind
    balance_sheet = %w[asset liability equity]

    if balance_sheet.include?(src_kind) && dest_kind == "expense"
      label, css = "↓ Withdrawal", "tx-type tx-type--withdrawal"
    elsif src_kind == "expense" && balance_sheet.include?(dest_kind)
      label, css = "↑ Refund", "tx-type tx-type--refund"
    elsif src_kind == "revenue" && balance_sheet.include?(dest_kind)
      label, css = "↑ Deposit", "tx-type tx-type--deposit"
    elsif balance_sheet.include?(src_kind) && dest_kind == "revenue"
      label, css = "↓ Clawback", "tx-type tx-type--clawback"
    else
      label, css = "⇄ Transfer", "tx-type tx-type--transfer"
    end

    tag.span(label, **html_options.merge(class: class_names(css, html_options[:class])))
  end

  def transaction_amount_with_currency(transaction)
    amount_to_currency(transaction.amount_minor, transaction.currency)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end
end
