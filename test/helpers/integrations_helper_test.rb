require "test_helper"

class IntegrationsHelperTest < ActionView::TestCase
  include CurrenciesHelper

  test "aggregator_balance formats a SimpleFIN balance in its currency" do
    assert_equal "$1,000.00", aggregator_balance(simplefin_accounts(:linked_one))
  end

  test "aggregator_balance formats a Lunch Flow balance in its currency" do
    assert_equal "$10,000.00", aggregator_balance(lunchflow_accounts(:unlinked_one))
  end

  test "aggregator_balance keeps the sign of a negative balance" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    simplefin_account.balance = "-250.50"

    assert_equal "-$250.50", aggregator_balance(simplefin_account)
  end

  test "aggregator_balance falls back to the raw value for an unknown currency" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.currency = "XYZ"
    lunchflow_account.balance = "123.45"

    assert_equal "123.45 XYZ", aggregator_balance(lunchflow_account)
  end

  test "aggregator_balance uses the reported currency, not the linked ledger account's" do
    simplefin_account = simplefin_accounts(:linked_one)
    assert_equal "USD", simplefin_account.ledger_account.currency.code
    simplefin_account.currency = "EUR"
    simplefin_account.balance = "100.00"

    assert_equal "€100.00", aggregator_balance(simplefin_account)
  end

  test "aggregator_balance falls back to the raw value for an unknown currency on a linked account" do
    lunchflow_account = lunchflow_accounts(:linked_one)
    assert lunchflow_account.linked?
    lunchflow_account.currency = "XYZ"

    assert_equal "2500.00 XYZ", aggregator_balance(lunchflow_account)
  end

  test "aggregator_balance returns a dash when no balance was reported" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.balance = nil

    assert_equal "—", aggregator_balance(lunchflow_account)
  end

  test "aggregator_currency returns the reported currency code" do
    assert_equal "USD", aggregator_currency(simplefin_accounts(:linked_one))
  end

  test "aggregator_currency flags a blank currency as missing" do
    simplefin_account = simplefin_accounts(:linked_one)
    simplefin_account.currency = ""

    marker = aggregator_currency(simplefin_account)
    assert_includes marker, "(missing)"
    # A theme-aware token that passes 4.5:1 contrast in both themes.
    assert_includes marker, "var(--accent-text)"
  end

  test "aggregator_currency flags a nil currency as missing" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.currency = nil

    assert_includes aggregator_currency(lunchflow_account), "(missing)"
  end
end
