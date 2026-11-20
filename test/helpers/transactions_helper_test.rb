require "test_helper"

class TransactionsHelperTest < ActionView::TestCase
  include CurrenciesHelper

  test "transaction_type_indicator for withdrawal" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:asset_account)
    transaction.dest_account = accounts(:expense_account)

    result = transaction_type_indicator(transaction)

    assert_match(/↓ Withdrawal/, result)
    assert_match(/tx-type--withdrawal/, result)
  end

  test "transaction_type_indicator for deposit" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:revenue_account)
    transaction.dest_account = accounts(:asset_account)

    result = transaction_type_indicator(transaction)

    assert_match(/↑ Deposit/, result)
    assert_match(/tx-type--deposit/, result)
  end

  test "transaction_type_indicator for refund" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:expense_account)
    transaction.dest_account = accounts(:asset_account)

    result = transaction_type_indicator(transaction)

    assert_match(/↑ Refund/, result)
    assert_match(/tx-type--refund/, result)
  end

  test "transaction_type_indicator for clawback" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:asset_account)
    transaction.dest_account = accounts(:revenue_account)

    result = transaction_type_indicator(transaction)

    assert_match(/↓ Clawback/, result)
    assert_match(/tx-type--clawback/, result)
  end


  test "transaction_type_indicator for transfer" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:asset_account)
    transaction.dest_account = accounts(:linked_asset)

    result = transaction_type_indicator(transaction)

    assert_match(/⇄ Transfer/, result)
    assert_match(/tx-type--transfer/, result)
  end

  test "transaction_type_indicator supports html options" do
    transaction = transactions(:one)
    transaction.src_account = accounts(:asset_account)
    transaction.dest_account = accounts(:linked_asset)

    result = transaction_type_indicator(transaction, class: "custom-class")

    assert_match(/tx-type tx-type--transfer/, result)
    assert_match(/custom-class/, result)
  end

  test "transaction_amount_with_currency formats amount with currency" do
    transaction = Transaction.new(amount_minor: 1500, currency: currencies(:usd))

    result = transaction_amount_with_currency(transaction)

    assert_equal "$15.00", result
  end

  test "transaction_fx_amount_with_currency formats FX amount when present" do
    transaction = Transaction.new(
      fx_amount_minor: 2000,
      fx_currency: currencies(:eur)
    )
    transaction.define_singleton_method(:has_fx?) { true }

    result = transaction_fx_amount_with_currency(transaction)

    assert_equal "€20.00", result
  end

  test "transaction_fx_amount_with_currency returns nil when no FX data" do
    transaction = Transaction.new
    transaction.define_singleton_method(:has_fx?) { false }

    result = transaction_fx_amount_with_currency(transaction)

    assert_nil result
  end

  test "transaction_amount_with_currency with JPY currency" do
    transaction = Transaction.new(amount_minor: 1500, currency: currencies(:jpy))

    result = transaction_amount_with_currency(transaction)

    assert_equal "¥1,500", result
  end

  test "transaction_amount_with_currency with crypto" do
    transaction = Transaction.new(amount_minor: 100000000, currency: currencies(:btc))

    result = transaction_amount_with_currency(transaction)

    assert_equal "₿1.00000000", result
  end


  test "transaction_account_field renders a button that opens edit mode on that account" do
    button = parse(transaction_account_field(transactions(:one), :src)).at_css("button.cell-edit.cell-edit--select")

    assert_equal "button", button["type"]
    # A mouse shortcut, kept out of the Tab order.
    assert_equal "-1", button["tabindex"]
    assert_equal "Asset Account", button.at_css(".cell-edit__value").text
    assert_equal "Asset Account", button["title"]
    assert_equal "transaction[src_account_id]", button["data-field"]
    assert_includes button["data-action"], "transactions--row#editField"
    assert_includes button["data-action"], "mouseenter->transactions--row#schedulePreload"
    assert_includes button["data-action"], "mouseleave->transactions--row#cancelPreload"
    assert_equal "From account: Asset Account. Edit transaction", button["aria-label"]
  end

  test "interactive cells carry a plain-text twin for phone widths" do
    transaction = transactions(:one)

    assert_equal "Asset Account", parse(transaction_account_field(transaction, :src)).at_css("span.cell-static").text
    assert_equal "Grocery Store", parse(transaction_description_field(transaction)).at_css("span.cell-static").text
    assert_equal "✓", parse(transaction_cleared_field(transaction, filter_account: nil)).at_css("span.cell-static").text
  end

  test "transaction_account_field targets the destination field for the To side" do
    button = parse(transaction_account_field(transactions(:one), :dest)).at_css("button")

    assert_equal "transaction[dest_account_id]", button["data-field"]
    assert_equal "To account: Expense Account. Edit transaction", button["aria-label"]
  end

  test "transaction_account_field is plain text for virtual accounts and opening balances" do
    opening_balance = transactions(:opening_balance_revenue)

    source = parse(transaction_account_field(opening_balance, :src))
    destination = parse(transaction_account_field(opening_balance, :dest))

    assert_equal "Opening Balance", source.at_css("span.cell-text").text
    assert_equal opening_balance.dest_account.name, destination.at_css("span.cell-text").text
    assert_nil source.at_css("button")
    assert_nil destination.at_css("button")
  end

  test "transaction_account_field is blank without an account" do
    assert_equal "", transaction_account_field(Transaction.new, :src)
  end

  test "transaction_category_field renders the category as an edit button" do
    transaction = transactions(:one)

    button = parse(transaction_category_field(transaction)).at_css("button.cell-edit--select")

    assert_equal transaction.category.name, button.at_css(".cell-edit__value").text
    assert_equal "transaction[category_id]", button["data-field"]
    assert_not_includes button["class"], "cell-edit--empty"
  end

  test "transaction_category_field marks an uncategorized transaction empty" do
    transaction = transactions(:one)
    transaction.category = nil

    button = parse(transaction_category_field(transaction)).at_css("button")

    assert_includes button["class"], "cell-edit--empty"
    assert_equal "Add category", button.at_css(".cell-edit__value")["data-placeholder"]
    assert_equal "Category: none. Edit transaction", button["aria-label"]
    assert_nil button["title"]
  end

  test "transaction_date_field renders the formatted date as an edit button" do
    transaction = transactions(:one)

    button = parse(transaction_date_field(transaction)).at_css("button")

    assert_equal transaction.transacted_at.strftime("%Y-%m-%d %I:%M %p"), button.text
    assert_equal "transaction[transacted_at]", button["data-field"]
    assert_not_includes button["class"], "cell-edit--select"
  end

  test "transaction_description_field renders the description as an edit button" do
    button = parse(transaction_description_field(transactions(:one))).at_css("button")

    assert_equal "Grocery Store", button.text
    assert_equal "transaction[description]", button["data-field"]
    assert_equal "Add description", button.at_css(".cell-edit__value")["data-placeholder"]
  end

  test "transaction_amount_field renders the formatted amount as an edit button" do
    button = parse(transaction_amount_field(transactions(:one))).at_css("button")

    assert_equal "$50.00", button.text
    assert_equal "transaction[amount]", button["data-field"]
  end

  test "transaction_cleared_field is a one-click form that unclears a cleared transaction" do
    transaction = transactions(:one)

    form = parse(transaction_cleared_field(transaction, filter_account: nil)).at_css("form.cleared-toggle")
    button = form.at_css("button.cell-edit")

    assert_equal transaction_path(transaction), form["action"]
    assert_equal "patch", form.at_css("input[name=_method]")["value"]
    assert_equal "0", form.at_css("input[name='transaction[cleared]']")["value"]
    assert_equal "✓", button.text
    assert_equal "true", button["aria-pressed"]
    assert_equal "Mark as not cleared", button["title"]
    # Saves on click rather than opening edit mode.
    assert_nil button["data-field"]
    # A rejected save opens edit mode to show the errors.
    assert_equal "turbo:submit-end->transactions--row#toggleSubmitEnd", form["data-action"]
  end

  test "transaction_cleared_field clears an uncleared transaction" do
    transaction = transactions(:one)
    transaction.cleared_at = nil

    form = parse(transaction_cleared_field(transaction, filter_account: nil))
    button = form.at_css("button")

    assert_equal "1", form.at_css("input[name='transaction[cleared]']")["value"]
    assert_includes button["class"], "cell-edit--empty"
    assert_equal "false", button["aria-pressed"]
    assert_equal "Mark as cleared", button["title"]
  end

  test "transaction_cleared_field keeps the index's account filter" do
    transaction = transactions(:one)
    account = accounts(:asset_account)

    form = parse(transaction_cleared_field(transaction, filter_account: account)).at_css("form")

    assert_equal transaction_path(transaction, account_id: account.id), form["action"]
  end

  test "transaction_amount_field_value keeps a whole amount's decimal places" do
    transaction = transactions(:one)

    assert_equal "50.00", transaction_amount_field_value(transaction)
  end

  test "transaction_amount_field_value uses the currency's precision" do
    transaction = transactions(:one)
    transaction.currency = currencies(:btc)
    transaction.amount_minor = 100_000_000

    assert_equal "1.00000000", transaction_amount_field_value(transaction)
  end

  test "transaction_amount_field_value returns a typed-in amount as entered" do
    transaction = transactions(:one)
    transaction.amount = "12.5"

    assert_equal "12.5", transaction_amount_field_value(transaction)
  end

  test "transaction_amount_field_value leaves a new transaction blank" do
    assert_nil transaction_amount_field_value(Transaction.new)
  end

  test "an opening balance renders every field as plain text" do
    transaction = transactions(:opening_balance_revenue)
    fields = [
      transaction_category_field(transaction),
      transaction_date_field(transaction),
      transaction_description_field(transaction),
      transaction_amount_field(transaction),
      transaction_cleared_field(transaction)
    ]

    fields.each { |field| assert_nil parse(field).at_css("button"), field }
    assert_equal "✓", transaction_cleared_field(transaction)
    assert_equal transaction_amount_with_currency(transaction), transaction_amount_field(transaction)
  end

  private

  def parse(html)
    Nokogiri::HTML5.fragment(html.to_s)
  end
end
