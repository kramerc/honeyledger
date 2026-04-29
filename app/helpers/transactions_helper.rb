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

  # Renders the amount with sign from the perspective of `perspective_account`:
  # negative when the account is the src side, positive when dest. Wraps the value
  # in a span carrying tx-amount--outflow / tx-amount--inflow for styling.
  def transaction_signed_amount_with_currency(transaction, perspective:)
    perspective ||= transaction.anchor_account
    return transaction_amount_with_currency(transaction) if perspective.nil?

    signed_minor = transaction.signed_amount_minor_for(perspective)
    css = signed_minor.negative? ? "tx-amount tx-amount--outflow" : "tx-amount tx-amount--inflow"
    tag.span(amount_to_currency(signed_minor, transaction.currency), class: css)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end

  # ---- Form helpers --------------------------------------------------------
  # On account-scoped views the anchor is implicit (= scoped_account). On the
  # unfiltered view the form needs an explicit anchor selector. The amount is
  # entered as a signed value (negative → outflow, positive → inflow); direction
  # is inferred server-side and the amount is stripped to its magnitude before
  # the model sees it.

  def transaction_form_anchor_id(transaction, scoped_account: nil)
    return scoped_account.id if scoped_account
    transaction.anchor_account&.id
  end

  def transaction_form_counterparty_id(transaction, scoped_account: nil)
    if scoped_account
      return transaction.dest_account_id if transaction.src_account_id == scoped_account.id
      return transaction.src_account_id if transaction.dest_account_id == scoped_account.id
      nil
    else
      transaction.counterparty_account&.id
    end
  end

  # Returns the amount as a signed string for display in the form input. Sign
  # is derived from whether the (in-memory) anchor is the src side. For
  # persisted transactions the magnitude is formatted to the currency's decimal
  # places via amount_minor_to_decimal.
  def transaction_form_amount(transaction, scoped_account: nil)
    raw_amount = transaction.amount
    return nil if raw_amount.nil? || raw_amount.to_s.empty?

    # Preserve the user's sign if they typed one (the controller may have
    # stripped it before the model saw it, but the literal string survives in
    # the @amount instance variable).
    if transaction.amount_written?
      raw = raw_amount.to_s
      return raw if raw.start_with?("-") || raw.start_with?("+")
    end

    anchor_id = transaction_form_anchor_id(transaction, scoped_account: scoped_account)
    is_outflow = anchor_id.present? && transaction.src_account_id == anchor_id

    magnitude = if transaction.amount_written?
      raw_amount.to_s
    elsif transaction.currency
      amount_minor_to_decimal(transaction.amount_minor, transaction.currency)
    else
      raw_amount.to_s
    end

    is_outflow ? "-#{magnitude}" : magnitude
  end
end
