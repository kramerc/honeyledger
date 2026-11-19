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

  test "aggregator_balance returns a dash when no balance was reported" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.balance = nil

    assert_equal "—", aggregator_balance(lunchflow_account)
  end
end
