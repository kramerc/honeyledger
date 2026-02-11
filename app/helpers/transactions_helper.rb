module TransactionsHelper
  def transaction_type_indicator(transaction)
    if transaction.dest_account.expense?
      tag.span("↓ Withdrawal", style: "color: red;")
    elsif transaction.src_account.revenue?
      tag.span("↑ Deposit", style: "color: green;")
    else
      tag.span("⇄ Transfer", style: "color: gray;")
    end
  end

  # Build <option> tags with data-kind and data-currency attributes for account selects.
  def account_options_with_kind(accounts, selected_id, prompt: nil)
    opts = []
    opts << content_tag(:option, prompt, value: "") if prompt
    accounts.each do |account|
      opts << content_tag(:option, account.name,
        value: account.id,
        selected: (account.id == selected_id ? "selected" : nil),
        data: { kind: account.kind, currency: account.currency.code })
    end
    safe_join(opts)
  end

  def transaction_amount_with_currency(transaction)
    amount_to_currency(transaction.amount_minor, transaction.currency)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end
end
