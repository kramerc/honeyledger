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

  # Editable cells. Each shows its value as a button; clicking it puts the
  # row into edit mode with that field focused, where Save confirms and
  # Cancel discards (see transactions--row#editField). Cleared is the one
  # exception and saves on click (#transaction_cleared_field). Opening balances
  # render every cell as plain text: they are edited through their account.

  # A From or To cell. Virtual counterparts also stay plain text, since the
  # edit form only offers real accounts.
  def transaction_account_field(transaction, side)
    account = side == :src ? transaction.src_account : transaction.dest_account
    return "" if account.nil?
    return plain_cell_text(account.name) if transaction.opening_balance? || account.virtual?

    edit_field_button :"#{side}_account_id", side == :src ? "From account" : "To account", account.name, modifier: "select"
  end

  def transaction_category_field(transaction)
    name = transaction.category&.name
    return name.to_s if transaction.opening_balance?

    edit_field_button :category_id, "Category", name, placeholder: "Add category", modifier: "select"
  end

  def transaction_date_field(transaction)
    formatted = transaction.transacted_at&.strftime("%Y-%m-%d %I:%M %p")
    return plain_cell_text(formatted) if transaction.opening_balance?

    edit_field_button :transacted_at, "Date", formatted
  end

  def transaction_description_field(transaction)
    description = transaction.description
    return plain_cell_text(description) if transaction.opening_balance?

    edit_field_button :description, "Description", description, placeholder: "Add description"
  end

  def transaction_amount_field(transaction)
    formatted = transaction_amount_with_currency(transaction)
    return formatted if transaction.opening_balance?

    edit_field_button :amount, "Amount", formatted
  end

  # The exception to edit mode: clicking Cleared saves the flipped status at
  # once. It PATCHes only `cleared`, and the update's Turbo Stream replaces
  # the row. account_id keeps the index's account filter, as in _form.
  def transaction_cleared_field(transaction, filter_account: @account)
    cleared = transaction.cleared_at.present?
    tick = cleared ? "✓" : ""
    return tick if transaction.opening_balance?

    button_to transaction_path(transaction, account_id: filter_account&.id),
      method: :patch,
      params: { "transaction[cleared]" => cleared ? "0" : "1" },
      form_class: "cleared-toggle",
      class: class_names("cell-edit", "cell-edit--empty" => !cleared),
      title: cleared ? "Mark as not cleared" : "Mark as cleared",
      aria: { label: "Cleared", pressed: cleared } do
      tag.span(tick, class: "cell-edit__value", data: { placeholder: "✓" })
    end
  end

  # The edit form's Amount value: a saved amount at its currency's full
  # precision ("15.00", not BigDecimal's "15.0"). An amount just typed in,
  # say on a rejected save, comes back as entered, and a new transaction's
  # field starts blank.
  def transaction_amount_field_value(transaction)
    return transaction.amount if transaction.amount_written? || transaction.new_record?

    number_with_precision(transaction.amount, precision: transaction.currency.decimal_places, delimiter: "")
  end

  def transaction_amount_with_currency(transaction)
    amount_to_currency(transaction.amount_minor, transaction.currency)
  end

  def transaction_fx_amount_with_currency(transaction)
    return nil unless transaction.has_fx?

    amount_to_currency(transaction.fx_amount_minor, transaction.fx_currency)
  end

  private

    def plain_cell_text(text)
      tag.span(text, class: "cell-text", title: text.presence)
    end

    # The value as a button. data-field names the edit form's field to focus;
    # hovering starts loading the row's lazy edit form so it's ready by the
    # click. modifier "select" adds a caret on hover for list-backed fields.
    def edit_field_button(attribute, label, value_text, modifier: nil, placeholder: nil)
      tag.button(type: "button",
        class: class_names("cell-edit", "cell-edit--#{modifier}" => modifier, "cell-edit--empty" => value_text.blank?),
        title: value_text.presence,
        aria: { label: "#{label}: #{value_text.presence || "none"}. Edit transaction" },
        data: {
          field: "transaction[#{attribute}]",
          action: "transactions--row#editField mouseenter->transactions--row#preloadEdit"
        }) do
        tag.span(value_text, class: "cell-edit__value", data: { placeholder: placeholder })
      end
    end
end
