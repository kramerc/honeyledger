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

  test "amount= setter converts decimal to minor units with 2 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    transaction.amount = "123.45"
    assert_equal 12345, transaction.amount_minor
  end

  test "amount= setter converts decimal to minor units with 0 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:jpy),
      transacted_at: Time.current
    )

    transaction.amount = "5000"
    assert_equal 5000, transaction.amount_minor
  end

  test "amount= setter converts decimal to minor units with 8 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:btc),
      transacted_at: Time.current
    )

    transaction.amount = "0.12345678"
    assert_equal 12345678, transaction.amount_minor
  end

  test "amount= setter rounds to nearest minor unit" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    # 123.456 should round to 123.46
    transaction.amount = "123.456"
    assert_equal 12346, transaction.amount_minor

    # 123.454 should round to 123.45
    transaction.amount = "123.454"
    assert_equal 12345, transaction.amount_minor
  end

  test "amount= setter handles BigDecimal input" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    transaction.amount = BigDecimal("99.99")
    assert_equal 9999, transaction.amount_minor
  end

  test "amount= setter handles integer input" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    transaction.amount = 50
    assert_equal 5000, transaction.amount_minor
  end

  test "fx_amount= setter converts decimal to minor units with 2 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      fx_currency: currencies(:eur),
      transacted_at: Time.current
    )

    transaction.fx_amount = "87.65"
    assert_equal 8765, transaction.fx_amount_minor
  end

  test "fx_amount= setter converts decimal to minor units with 0 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      fx_currency: currencies(:jpy),
      transacted_at: Time.current
    )

    transaction.fx_amount = "10000"
    assert_equal 10000, transaction.fx_amount_minor
  end

  test "fx_amount= setter converts decimal to minor units with 8 decimal places" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      fx_currency: currencies(:btc),
      transacted_at: Time.current
    )

    transaction.fx_amount = "0.00123456"
    assert_equal 123456, transaction.fx_amount_minor
  end

  test "fx_amount= setter rounds to nearest minor unit" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:two),
      currency: currencies(:usd),
      fx_currency: currencies(:eur),
      transacted_at: Time.current
    )

    # 50.556 should round to 50.56
    transaction.fx_amount = "50.556"
    assert_equal 5056, transaction.fx_amount_minor

    # 50.554 should round to 50.55
    transaction.fx_amount = "50.554"
    assert_equal 5055, transaction.fx_amount_minor
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

  test "currency is automatically set from dest account" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:expense_account),
      amount_minor: 1000,
      description: "Test",
      transacted_at: Time.current
    )

    assert transaction.valid?
    assert_equal accounts(:expense_account).currency_id, transaction.currency_id
  end

  test "currency auto-corrected from dest account when initially mismatched" do
    # Create a dest account with EUR currency to force a mismatch
    eur_account = Account.create!(
      user: users(:one),
      currency: currencies(:eur),
      name: "EUR Expense",
      kind: :expense
    )

    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: eur_account,
      amount_minor: 1000,
      description: "Test",
      currency: currencies(:usd), # mismatch
      transacted_at: Time.current
    )

    # before_validation will correct it, so the validation should pass
    assert transaction.valid?
    assert_equal currencies(:eur).id, transaction.currency_id, "Currency should be auto-corrected to dest account currency"
  end
end
