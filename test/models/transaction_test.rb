require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "amount returns correct decimal value based on currency decimal places" do
    transaction = transactions(:one)
    # amount_minor is 5000, currency has 2 decimal places
    assert_equal BigDecimal("50.00"), transaction.amount
  end

  test "amount handles different decimal places" do
    # Use a currency with 0 decimal places (like JPY)
    currency_jpy = currencies(:jpy)

    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currency_jpy,
      amount_minor: 5000,
      transacted_at: Time.current
    )

    assert_equal BigDecimal("5000"), transaction.amount
  end

  test "fx_amount returns nil when fx_amount_minor is nil" do
    transaction = transactions(:one)
    assert_nil transaction.fx_amount
  end

  test "fx_amount returns nil when fx_currency is nil" do
    transaction = transactions(:one)
    transaction.fx_amount_minor = 10000
    assert_nil transaction.fx_amount
  end

  test "fx_amount returns correct decimal value when both fx_amount_minor and fx_currency are present" do
    transaction = transactions(:one)
    transaction.fx_currency = currencies(:eur)
    transaction.fx_amount_minor = 4500

    # 4500 with 2 decimal places = 45.00
    assert_equal BigDecimal("45.00"), transaction.fx_amount
  end

  test "creating child transaction marks parent as split" do
    parent = transactions(:one)
    assert_not parent.split, "Parent should not be split initially"

    _child = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      description: "Child transaction",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    parent.reload
    assert parent.split, "Parent should be marked as split after creating child"
  end

  test "destroying last child transaction unmarks parent as split" do
    parent = transactions(:one)

    # Create a child transaction
    child = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      description: "Child transaction",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    parent.reload
    assert parent.split, "Parent should be marked as split"

    # Destroy the child
    child.destroy

    parent.reload
    assert_not parent.split, "Parent should not be marked as split after last child is destroyed"
  end

  test "destroying one of multiple children keeps parent marked as split" do
    parent = transactions(:one)

    # Create two child transactions
    child1 = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      description: "Child transaction 1",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    _child2 = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      description: "Child transaction 2",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    parent.reload
    assert parent.split, "Parent should be marked as split"

    # Destroy one child
    child1.destroy

    parent.reload
    assert parent.split, "Parent should still be marked as split when children remain"
  end

  test "destroying parent destroys child transactions" do
    parent = transactions(:one)

    child = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      description: "Child transaction",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    child_id = child.id

    parent.destroy

    assert_nil Transaction.find_by(id: child_id), "Child transaction should be destroyed with parent"
  end
end
