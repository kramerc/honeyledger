require "test_helper"

class Transaction::InferLedgerSideTest < ActiveSupport::TestCase
  test "puts the ledger account on src for a negative amount" do
    result = infer("Coffee Shop", -5000)

    assert_equal :src, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "puts the ledger account on dest for a positive amount" do
    result = infer("Salary Payment", 250_000)

    assert_equal :dest, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "treats a zero amount as an inflow" do
    result = infer("Fee Waiver", 0)

    assert_equal :dest, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "overrides a negative TRANSFERRED FROM row onto dest (#222)" do
    result = infer("TRANSFERRED FROM ACCT ****0001", -3826)

    assert_equal :dest, result.ledger_side
    assert result.direction_overridden?
  end

  test "leaves a positive TRANSFERRED FROM row alone so the fix self-heals (#222)" do
    result = infer("TRANSFERRED FROM ACCT ****0001", 3826)

    assert_equal :dest, result.ledger_side
    assert_not result.direction_overridden?,
      "a correctly-signed inflow needs no override, so the rule must go quiet on its own"
  end

  test "leaves a negative TRANSFERRED TO row on src" do
    result = infer("TRANSFERRED TO ACCT ****0002", -3826)

    assert_equal :src, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "matches the un-suffixed TRANSFER FROM form" do
    assert infer("TRANSFER FROM ACCT ****0001", -3826).direction_overridden?
  end

  test "matches when the counterparty token follows FROM directly" do
    assert infer("TRANSFERRED FROM ****0001", -3826).direction_overridden?
  end

  test "matches case-insensitively" do
    assert infer("transferred from acct ****0001", -3826).direction_overridden?
  end

  test "matches across extra whitespace" do
    assert infer("TRANSFERRED   FROM ACCT ****0001", -3826).direction_overridden?
  end

  test "matches an inbound wire worded WIRE TRANSFER FROM" do
    assert infer("WIRE TRANSFER FROM ACCT ****0001", -3826).direction_overridden?
  end

  test "does not match FROM inside a longer word" do
    result = infer("TRANSFERRED FROMAGE CO", -3826)

    assert_equal :src, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "requires TRANSFER and FROM to be adjacent" do
    result = infer("TRANSFER TO ACCT ****0002 FROM ACCT ****0001", -3826)

    assert_equal :src, result.ledger_side
    assert_not result.direction_overridden?
  end

  test "does not match a nil description" do
    result = infer(nil, -3826)

    assert_equal :src, result.ledger_side
    assert_not result.direction_overridden?
  end

  private

    def infer(description, amount_minor)
      Transaction::InferLedgerSide.call(description: description, amount_minor: amount_minor)
    end
end
