require "test_helper"

class Simplefin::TransactionTest < ActiveSupport::TestCase
  setup do
    @simplefin_transaction = simplefin_transactions(:transaction_one)
  end

  test "belongs to account" do
    assert_equal simplefin_accounts(:linked_one), @simplefin_transaction.account
  end

  test "resolved_description passes the description through" do
    assert_equal @simplefin_transaction.description, @simplefin_transaction.resolved_description
  end

  test "ledger_direction puts a negative amount on src" do
    direction = @simplefin_transaction.ledger_direction

    assert_equal :src, direction.ledger_side
    assert_not direction.direction_overridden?
  end

  test "ledger_direction puts a non-negative amount on dest" do
    @simplefin_transaction.amount = "50.00"

    assert_equal :dest, @simplefin_transaction.ledger_direction.ledger_side
  end

  test "ledger_direction flips a negative inbound transfer to dest" do
    @simplefin_transaction.description = "TRANSFERRED FROM Test Savings"
    direction = @simplefin_transaction.ledger_direction

    assert_equal :dest, direction.ledger_side
    assert direction.direction_overridden?
  end

  test "signed_ledger_amount is negative for an outflow" do
    assert_equal(-50.to_d, @simplefin_transaction.signed_ledger_amount)
  end

  test "signed_ledger_amount is positive for an inflow" do
    @simplefin_transaction.amount = "50.00"

    assert_equal 50.to_d, @simplefin_transaction.signed_ledger_amount
  end

  test "signed_ledger_amount is positive for a negative inbound transfer" do
    @simplefin_transaction.amount = "-20.00"
    @simplefin_transaction.description = "TRANSFERRED FROM Test Savings"

    assert_equal 20.to_d, @simplefin_transaction.signed_ledger_amount
  end

  test "signed_ledger_amount is zero when the feed sent no amount" do
    @simplefin_transaction.amount = nil

    assert_nil @simplefin_transaction.amount_minor
    assert_equal 0.to_d, @simplefin_transaction.signed_ledger_amount
  end
end
