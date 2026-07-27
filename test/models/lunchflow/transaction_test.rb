require "test_helper"

class Lunchflow::TransactionTest < ActiveSupport::TestCase
  setup do
    @lunchflow_transaction = lunchflow_transactions(:transaction_one)
  end

  test "belongs to account" do
    assert_equal lunchflow_accounts(:linked_one), @lunchflow_transaction.account
  end

  test "resolved_description prefers the merchant" do
    assert_equal @lunchflow_transaction.merchant, @lunchflow_transaction.resolved_description
  end

  test "resolved_description falls back to the description when merchant is blank" do
    @lunchflow_transaction.merchant = ""

    assert_equal @lunchflow_transaction.description, @lunchflow_transaction.resolved_description
  end

  test "ledger_direction puts a negative amount on src" do
    direction = @lunchflow_transaction.ledger_direction

    assert_equal :src, direction.ledger_side
    assert_not direction.direction_overridden?
  end

  test "ledger_direction reads the transfer wording from the merchant" do
    @lunchflow_transaction.merchant = "TRANSFERRED FROM Test Savings"
    direction = @lunchflow_transaction.ledger_direction

    assert_equal :dest, direction.ledger_side
    assert direction.direction_overridden?
  end

  test "ledger_direction ignores transfer wording the merchant shadows" do
    @lunchflow_transaction.merchant = "Test Merchant"
    @lunchflow_transaction.description = "TRANSFERRED FROM Test Savings"

    assert_equal :src, @lunchflow_transaction.ledger_direction.ledger_side
  end

  test "signed_ledger_amount is negative for an outflow" do
    assert_equal(-75.to_d, @lunchflow_transaction.signed_ledger_amount)
  end

  test "signed_ledger_amount is positive for a negative inbound transfer" do
    @lunchflow_transaction.amount = "-20.00"
    @lunchflow_transaction.merchant = "TRANSFERRED FROM Test Savings"

    assert_equal 20.to_d, @lunchflow_transaction.signed_ledger_amount
  end

  test "signed_ledger_amount is zero when the feed sent no amount" do
    @lunchflow_transaction.amount = nil

    assert_nil @lunchflow_transaction.amount_minor
    assert_equal 0.to_d, @lunchflow_transaction.signed_ledger_amount
  end
end
