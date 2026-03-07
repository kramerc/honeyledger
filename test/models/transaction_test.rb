require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "creating child transaction marks parent as split" do
    parent = transactions(:one)
    assert_not parent.split, "Parent should not be split initially"

    _child = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:asset_account),
      dest_account: accounts(:liability_account),
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
      src_account: accounts(:asset_account),
      dest_account: accounts(:liability_account),
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
      src_account: accounts(:asset_account),
      dest_account: accounts(:liability_account),
      description: "Child transaction 1",
      amount_minor: 2500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    _child2 = Transaction.create!(
      user: users(:one),
      parent_transaction: parent,
      category: categories(:one),
      src_account: accounts(:asset_account),
      dest_account: accounts(:liability_account),
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
      src_account: accounts(:asset_account),
      dest_account: accounts(:liability_account),
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

  test "cleared returns true when cleared_at is present" do
    transaction = transactions(:one)
    assert transaction.cleared_at.present?
    assert_equal true, transaction.cleared
  end

  test "cleared returns false when cleared_at is nil" do
    transaction = transactions(:one)
    transaction.cleared_at = nil
    assert_equal false, transaction.cleared
  end

  test "cleared setter casts string '1' to true" do
    transaction = transactions(:one)
    transaction.cleared = "1"
    assert_equal true, transaction.cleared
  end

  test "cleared setter casts string '0' to false" do
    transaction = transactions(:one)
    transaction.cleared = "0"
    assert_equal false, transaction.cleared
  end

  test "setting cleared to true sets cleared_at when nil" do
    transaction = transactions(:one)
    transaction.cleared_at = nil
    transaction.cleared = "1"

    freeze_time do
      transaction.valid?
      assert_equal Time.current, transaction.cleared_at
    end
  end

  test "setting cleared to true preserves existing cleared_at timestamp" do
    transaction = transactions(:one)
    original_cleared_at = transaction.cleared_at
    transaction.cleared = "1"
    transaction.valid?

    assert_equal original_cleared_at, transaction.cleared_at
  end

  test "setting cleared to false clears cleared_at" do
    transaction = transactions(:one)
    assert transaction.cleared_at.present?
    transaction.cleared = "0"
    transaction.valid?

    assert_nil transaction.cleared_at
  end

  test "not setting cleared leaves cleared_at unchanged" do
    transaction = transactions(:one)
    original_cleared_at = transaction.cleared_at
    transaction.description = "Updated"
    transaction.valid?

    assert_equal original_cleared_at, transaction.cleared_at
  end

  test "saving a transaction with a new amount decrements src account balance_minor by the difference" do
    transaction = transactions(:one)
    src = transaction.src_account
    src.reset_balance
    original_balance = src.balance_minor

    transaction.update!(amount_minor: transaction.amount_minor + 1000)

    assert_equal original_balance - 1000, src.reload.balance_minor
  end

  test "saving a transaction with a new amount increments dest account balance_minor by the difference" do
    transaction = transactions(:one)
    dest = transaction.dest_account
    dest.reset_balance
    original_balance = dest.balance_minor

    transaction.update!(amount_minor: transaction.amount_minor + 1000)

    assert_equal original_balance + 1000, dest.reload.balance_minor
  end

  test "saving a transaction without changing amount does not update account balances" do
    transaction = transactions(:one)
    src = transaction.src_account
    dest = transaction.dest_account
    src.reset_balance
    dest.reset_balance
    src_balance = src.balance_minor
    dest_balance = dest.balance_minor

    transaction.update!(description: "Updated description")

    assert_equal src_balance, src.reload.balance_minor
    assert_equal dest_balance, dest.reload.balance_minor
  end

  test "destroying a transaction increments src account balance_minor" do
    transaction = transactions(:one)
    src = transaction.src_account
    src.reset_balance
    original_balance = src.balance_minor

    transaction.destroy!

    assert_equal original_balance + transaction.amount_minor, src.reload.balance_minor
  end

  test "destroying a transaction decrements dest account balance_minor" do
    transaction = transactions(:one)
    dest = transaction.dest_account
    dest.reset_balance
    original_balance = dest.balance_minor

    transaction.destroy!

    assert_equal original_balance - transaction.amount_minor, dest.reload.balance_minor
  end

  test "validates src_account is accessible to user" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:two), # belongs to users(:two)
      dest_account: accounts(:asset_account),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:src_account], "must be accessible to you"
  end

  test "validates dest_account is accessible to user" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:asset_account),
      dest_account: accounts(:two), # belongs to users(:two)
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must be accessible to you"
  end

  test "validates accounts cannot be the same" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:one),
      dest_account: accounts(:one),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:src_account], "cannot be the same as dest account"
  end

  test "validates not revenue to expense" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:revenue_account),
      dest_account: accounts(:expense_account),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:src_account], "cannot be a revenue account to an expense dest account"
  end

  test "validates not expense to revenue" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:expense_account),
      dest_account: accounts(:revenue_account),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:src_account], "cannot be an expense account to a revenue dest account"
  end

  test "has_fx? returns true when fx_amount_minor and fx_currency are present" do
    transaction = transactions(:one)
    transaction.fx_amount_minor = 1200
    transaction.fx_currency = currencies(:eur)

    assert transaction.has_fx?
  end

  test "has_fx? returns false when fx fields are absent" do
    transaction = transactions(:one)

    assert_not transaction.has_fx?
  end

  test "opening_balance_target_account returns nil for a regular transaction" do
    assert_nil transactions(:one).opening_balance_target_account
  end

  test "opening_balance_target_account returns the real dest account for a positive opening balance" do
    # src is the virtual opening balance revenue account; dest is the real asset account
    t = transactions(:opening_balance_revenue)
    assert_equal accounts(:asset_account_with_opening_balance), t.opening_balance_target_account
  end

  test "opening_balance_target_account returns the real src account for a negative opening balance" do
    # src is the real liability account; dest is the virtual opening balance expense account
    t = transactions(:opening_balance_expense)
    assert_equal accounts(:liability_account_with_opening_balance), t.opening_balance_target_account
  end
end
