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

  test "destroying a transaction with reassigned accounts in-memory reverses balances on original accounts" do
    transaction = transactions(:one)
    original_src = transaction.src_account
    original_dest = transaction.dest_account
    original_src.reset_balance
    original_dest.reset_balance
    original_src_balance = original_src.balance_minor
    original_dest_balance = original_dest.balance_minor

    # Reassign accounts in-memory without saving — destroy! should still reverse the originally persisted accounts
    transaction.src_account = accounts(:liability_account)
    transaction.dest_account = accounts(:asset_account)
    transaction.destroy!

    assert_equal original_src_balance + transaction.amount_minor, original_src.reload.balance_minor
    assert_equal original_dest_balance - transaction.amount_minor, original_dest.reload.balance_minor
  end

  test "creating a transaction decrements src account balance_minor" do
    src = accounts(:asset_account)
    src.reset_balance
    original_balance = src.balance_minor

    Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: src,
      dest_account: accounts(:expense_account),
      description: "New purchase",
      amount_minor: 3000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_equal original_balance - 3000, src.reload.balance_minor
  end

  test "creating a transaction increments dest account balance_minor" do
    dest = accounts(:asset_account)
    dest.reset_balance
    original_balance = dest.balance_minor

    Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: accounts(:revenue_account),
      dest_account: dest,
      description: "Income",
      amount_minor: 7500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_equal original_balance + 7500, dest.reload.balance_minor
  end

  test "moving a transaction to different accounts updates all affected balances" do
    transaction = transactions(:one)
    old_src = transaction.src_account
    old_dest = transaction.dest_account
    new_src = accounts(:revenue_account)
    new_dest = accounts(:liability_account)

    old_src.reset_balance
    old_dest.reset_balance
    new_src.reset_balance
    new_dest.reset_balance

    old_src_balance = old_src.balance_minor
    old_dest_balance = old_dest.balance_minor
    new_src_balance = new_src.balance_minor
    new_dest_balance = new_dest.balance_minor
    amount = transaction.amount_minor

    transaction.update!(src_account: new_src, dest_account: new_dest)

    assert_equal old_src_balance + amount, old_src.reload.balance_minor
    assert_equal old_dest_balance - amount, old_dest.reload.balance_minor
    assert_equal new_src_balance - amount, new_src.reload.balance_minor
    assert_equal new_dest_balance + amount, new_dest.reload.balance_minor
  end


  test "creating an FX transaction decrements src account by fx_amount_minor" do
    eur_src = accounts(:eur_asset_account)
    eur_src.reset_balance
    dest = accounts(:expense_account)
    dest.reset_balance
    src_balance = eur_src.balance_minor
    dest_balance = dest.balance_minor

    Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: eur_src,
      dest_account: dest,
      amount_minor: 5000,
      fx_amount_minor: 4600,
      fx_currency: currencies(:eur),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_equal src_balance - 4600, eur_src.reload.balance_minor
    assert_equal dest_balance + 5000, dest.reload.balance_minor
  end

  test "creating an FX transaction increments dest account by amount_minor not fx_amount_minor" do
    eur_src = accounts(:eur_asset_account)
    dest = accounts(:asset_account)
    dest.reset_balance
    dest_balance = dest.balance_minor

    Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: eur_src,
      dest_account: dest,
      amount_minor: 5000,
      fx_amount_minor: 4600,
      fx_currency: currencies(:eur),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_equal dest_balance + 5000, dest.reload.balance_minor
  end

  test "destroying an FX transaction reverses src by fx_amount_minor and dest by amount_minor" do
    eur_src = accounts(:eur_asset_account)
    dest = accounts(:expense_account)

    transaction = Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: eur_src,
      dest_account: dest,
      amount_minor: 5000,
      fx_amount_minor: 4600,
      fx_currency: currencies(:eur),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    eur_src.reset_balance
    dest.reset_balance
    src_balance = eur_src.balance_minor
    dest_balance = dest.balance_minor

    transaction.destroy!

    assert_equal src_balance + 4600, eur_src.reload.balance_minor
    assert_equal dest_balance - 5000, dest.reload.balance_minor
  end

  test "updating fx_amount_minor adjusts src account by the difference" do
    eur_src = accounts(:eur_asset_account)
    dest = accounts(:expense_account)

    transaction = Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: eur_src,
      dest_account: dest,
      amount_minor: 5000,
      fx_amount_minor: 4600,
      fx_currency: currencies(:eur),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    eur_src.reset_balance
    src_balance = eur_src.balance_minor

    transaction.update!(fx_amount_minor: 4800)

    assert_equal src_balance - 200, eur_src.reload.balance_minor
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

  test "validates revenue to expense is invalid" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:revenue_account),
      dest_account: accounts(:expense_account),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must be an asset, liability, or equity account"
    assert_includes transaction.errors[:src_account], "must be an asset, liability, or equity account"
  end

  test "validates expense to revenue is invalid" do
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:expense_account),
      dest_account: accounts(:revenue_account),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must be an asset, liability, or equity account"
  end

  test "validates expense to expense is invalid" do
    second_expense = Account.create!(user: users(:one), currency: currencies(:usd), name: "Other Expense", kind: :expense)
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:expense_account),
      dest_account: second_expense,
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must be an asset, liability, or equity account"
  end

  test "validates revenue to revenue is invalid" do
    second_revenue = Account.create!(user: users(:one), currency: currencies(:usd), name: "Other Revenue", kind: :revenue)
    transaction = Transaction.new(
      user: users(:one),
      src_account: accounts(:revenue_account),
      dest_account: second_revenue,
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must be an asset, liability, or equity account"
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

  test "src_account is required for opening balance transactions" do
    transaction = Transaction.new(
      user: users(:two),
      dest_account: accounts(:asset_account_with_opening_balance),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: 1.month.ago,
      opening_balance: true
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:src_account], "must exist"
  end

  test "dest_account is required for opening balance transactions" do
    transaction = Transaction.new(
      user: users(:two),
      src_account: accounts(:opening_balance_revenue),
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: 1.month.ago,
      opening_balance: true
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:dest_account], "must exist"
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
