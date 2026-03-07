require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
  end

  test "opening_balance_for finds existing opening balance account" do
    account = accounts(:opening_balance_expense)

    assert_no_difference("Account.count") do
      assert_equal account, Account.opening_balance_for(user: account.user, kind: account.kind)
    end
  end

  test "opening_balance_for creates new opening balance account it doesn't exist" do
    assert_difference("Account.count") do
      Account.opening_balance_for(user: users(:one), kind: :expense)
    end
  end

  test "opening_balance_for raises RecordInvalid when invalid" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Account.opening_balance_for(user: nil, kind: :expense)
    end
  end

  test "opening_balance_for handles RecordNotUnique" do
    Account.stub :find_or_create_by!, ->(_) { raise ActiveRecord::RecordNotUnique } do
      Account.stub(:find_by, @account) do
        assert_no_difference("Account.count") do
          assert_equal @account, Account.opening_balance_for(user: users(:one), kind: :revenue)
        end
      end
    end
  end

  test "opening_balance_for raises RecordNotUnique when both find and create fail" do
    Account.stub :find_or_create_by!, ->(_) { raise ActiveRecord::RecordNotUnique } do
      Account.stub(:find_by, nil) do
        assert_raises(ActiveRecord::RecordNotUnique) do
          Account.opening_balance_for(user: users(:one), kind: :revenue)
        end
      end
    end
  end

  test "linkable scope returns only asset and liability accounts" do
    linkable = Account.linkable

    assert_includes linkable, accounts(:asset_account)
    assert_includes linkable, accounts(:liability_account)
    assert_includes linkable, accounts(:linked_asset)
    assert_includes linkable, accounts(:unlinked_liability)

    assert_not_includes linkable, accounts(:expense_account)
    assert_not_includes linkable, accounts(:revenue_account)
  end

  test "unlinked scope returns accounts without simplefin_account association" do
    unlinked = Account.unlinked

    assert_includes unlinked, accounts(:asset_account)
    assert_includes unlinked, accounts(:liability_account)
    assert_includes unlinked, accounts(:expense_account)
    assert_includes unlinked, accounts(:revenue_account)
    assert_includes unlinked, accounts(:unlinked_liability)

    assert_not_includes unlinked, accounts(:linked_asset)
  end

  test "linkable.unlinked chains scopes correctly" do
    linkable_unlinked = Account.linkable.unlinked

    assert_includes linkable_unlinked, accounts(:asset_account)
    assert_includes linkable_unlinked, accounts(:liability_account)
    assert_includes linkable_unlinked, accounts(:unlinked_liability)

    # Linked account should be excluded
    assert_not_includes linkable_unlinked, accounts(:linked_asset)

    # Non-linkable accounts should be excluded
    assert_not_includes linkable_unlinked, accounts(:expense_account)
    assert_not_includes linkable_unlinked, accounts(:revenue_account)
  end

  test "empty? is false if account contains transactions" do
    @account.dest_transactions << transactions(:one)

    assert_not @account.empty?
  end

  test "empty? is true if account has no transactions" do
    @account.src_transactions.destroy_all
    @account.dest_transactions.destroy_all

    assert @account.empty?
  end

  test "empty? is true if account only has an opening balance transaction" do
    @account.src_transactions.destroy_all
    @account.dest_transactions.destroy_all
    @account.opening_balance_amount = "10.00"
    @account.opening_balance_transacted_at = 1.month.ago

    @account.save!

    assert_not_nil @account.opening_balance_transaction
    assert_equal 1, @account.dest_transactions.count
    assert @account.empty?
  end

  test "real? is true if account is not virtual" do
    assert @account.real?
  end

  test "updates associated accounts on positive opening balance" do
    account = accounts(:liability_account_with_opening_balance)
    account.opening_balance_amount = "10.00"
    account.opening_balance_transacted_at = 1.month.ago

    account.save!
    t = account.opening_balance_transaction

    assert_equal Account.opening_balance_for(user: account.user, kind: :revenue), t.src_account
    assert_equal account, t.dest_account
  end

  test "updates associated accounts on negative opening balance" do
    account = accounts(:asset_account_with_opening_balance)
    account.opening_balance_amount = "-10.00"
    account.opening_balance_transacted_at = 1.month.ago

    account.save!
    t = account.opening_balance_transaction

    assert_equal account, t.src_account
    assert_equal Account.opening_balance_for(user: account.user, kind: :expense), t.dest_account
    assert_equal 1000, t.amount_minor, "negative opening balance amount_minor should be persisted as its absolute value"
  end

  test "opening balance matches account's currency after save" do
    account = accounts(:asset_account_with_opening_balance)
    account.opening_balance_amount = "5.00"
    account.opening_balance_transacted_at = 1.month.ago

    account.save!

    assert_equal account.currency, account.opening_balance_transaction.currency
  end

  test "cleared_at matches transacted_at for opening balance" do
    account = accounts(:asset_account_with_opening_balance)
    date = 6.months.ago
    account.opening_balance_amount = "5.00"
    account.opening_balance_transacted_at = date

    account.save!
    t = account.opening_balance_transaction

    assert_equal t.transacted_at, t.cleared_at
  end

  test "opening_balance_amount_minor returns positive for asset account with positive opening balance" do
    account = accounts(:asset_account_with_opening_balance)

    assert_equal 1000, account.opening_balance_amount_minor
  end

  test "opening_balance_amount_minor returns negative for liability account with negative opening balance" do
    account = accounts(:liability_account_with_opening_balance)

    assert_equal(-1000, account.opening_balance_amount_minor)
  end

  test "opening_balance_amount_minor returns nil when no opening balance transaction" do
    assert_nil @account.opening_balance_amount_minor
  end

  test "opening_balance_amount reads positive amount from persisted transaction" do
    # src_account is the virtual opening balance revenue account (real? = false)
    # so the ternary takes the false branch and returns t.amount directly (positive)
    account = accounts(:asset_account_with_opening_balance)
    assert account.opening_balance_amount > 0
  end

  test "opening_balance_amount reads negative amount from persisted transaction" do
    # src_account is the account itself (real? = true)
    # so the ternary takes the true branch and returns -t.amount (negative)
    account = accounts(:liability_account_with_opening_balance)
    assert account.opening_balance_amount < 0
  end

  test "real? is false if account is virtual" do
    @account.update!(virtual: true)

    assert_not @account.real?
  end

  test "does not include opening balance accounts in sourceable/destinable scopes" do
    assert_not Account.sourceable.include?(accounts(:opening_balance_revenue))
    assert_not Account.destinable.include?(accounts(:opening_balance_expense))
  end

  test "account is valid if opening_balance_amount is blank" do
    @account.opening_balance_amount = ""
    @account.opening_balance_transacted_at = 1.month.ago

    assert @account.valid?
  end

  test "account is valid when both opening balance fields submitted blank (e.g. from form)" do
    # Regression: assigning blank values for both fields should not trigger
    # opening balance callbacks, so a nil transacted_at must not cause a
    # validation error when no opening balance is being set.
    @account.opening_balance_amount = ""
    @account.opening_balance_transacted_at = nil

    assert @account.valid?
  end

  test "account is valid if opening_balance_amount is zero" do
    @account.opening_balance_amount = 0
    @account.opening_balance_transacted_at = 1.month.ago

    assert @account.valid?
  end

  test "account is invalid if opening_balance_amount is not a number" do
    @account.opening_balance_amount = "invalid"
    @account.opening_balance_transacted_at = 1.month.ago

    assert @account.invalid?
    assert_includes @account.errors["opening_balance_amount"], "is not a number"
  end

  test "account is invalid if opening_balance_amount is set on an expense account" do
    account = accounts(:expense_account)
    account.opening_balance_amount = "10.00"
    account.opening_balance_transacted_at = 1.month.ago

    assert account.invalid?
    assert_includes account.errors[:opening_balance_amount], "is not allowed for expense accounts"
  end

  test "account is invalid if opening_balance_transacted_at is blank" do
    @account.opening_balance_amount = 1
    @account.opening_balance_transacted_at = nil

    assert @account.invalid?
    assert_includes @account.errors["opening_balance_transacted_at"], "can't be blank"
  end

  test "opening balance transaction errors on unknown attributes propagate with generic attribute name" do
    # Trigger an error the opening balance transaction for an attribute that is not
    # :amount, :amount_minor, or :transacted_at so the else branch in the case stmt is exercised.
    # A nil currency causes a :currency error on the transaction.
    account = Account.new(name: "Test", kind: :asset, user: users(:one), virtual: false)
    account.opening_balance_amount = "10.00"
    account.opening_balance_transacted_at = 1.month.ago

    account.valid?

    assert account.errors[:"opening_balance_transaction.currency"].present?
  end

  test "opening balance transaction is saved on account save" do
    @account.opening_balance_amount = "1"
    @account.opening_balance_transacted_at = 1.month.ago
    assert @account.opening_balance_transaction.nil?

    @account.save!

    assert @account.opening_balance_transaction.persisted?
  end

  test "updating only opening_balance_transacted_at re-saves existing opening balance transaction" do
    # Exercises the else branch in assign_opening_balance_transaction_attributes and the
    # amount_minor.to_i.zero? path in save_or_destroy, reached when @opening_balance_amount
    # is not set but an opening balance transaction already exists.
    account = accounts(:asset_account_with_opening_balance)
    new_date = 2.months.ago
    account.opening_balance_transacted_at = new_date

    account.save!

    assert_in_delta new_date, account.opening_balance_transaction.transacted_at, 1.second
  end

  test "updating only opening_balance_transacted_at preserves direction of a negative opening balance" do
    # Regression: direction must be derived from src/dest account roles, not from
    # the sign of amount_minor (which is now always stored positive).
    account = accounts(:liability_account_with_opening_balance)
    original_src = account.opening_balance_transaction.src_account
    new_date = 3.months.ago
    account.opening_balance_transacted_at = new_date

    account.save!

    assert_equal original_src, account.opening_balance_transaction.src_account
    assert_in_delta new_date, account.opening_balance_transaction.transacted_at, 1.second
  end

  test "opening balance transaction is destroyed if amount is blank" do
    @account.opening_balance_amount = "1"
    @account.opening_balance_transacted_at = 1.month.ago

    @account.save!

    @account.opening_balance_amount = ""

    assert_difference("Transaction.count", -1) do
      @account.save!
    end

    assert_nil @account.opening_balance_transaction, "memoized opening_balance_transaction should be cleared after destroy"
  end

  test "opening balance transaction is destroyed if amount is zero" do
    @account.opening_balance_amount = "1"
    @account.opening_balance_transacted_at = 1.month.ago

    @account.save!

    @account.opening_balance_amount = 0

    assert_difference("Transaction.count", -1) do
      @account.save!
    end
  end

  test "destroys account with only a revenue opening balance transaction" do
    @account.opening_balance_amount = "10.00"
    @account.opening_balance_transacted_at = Time.current
    @account.save!
    transaction = @account.opening_balance_transaction

    assert_difference("Account.count", -1) do
      @account.destroy
    end

    assert_raises(ActiveRecord::RecordNotFound) { transaction.reload }
  end

  test "destroys account with only a expense opening balance transaction" do
    @account.opening_balance_amount = "-10.00"
    @account.opening_balance_transacted_at = Time.current
    @account.save!
    transaction = @account.opening_balance_transaction

    assert_difference("Account.count", -1) do
      @account.destroy
    end

    assert_raises(ActiveRecord::RecordNotFound) { transaction.reload }
  end

  test "does not destroy account with one non-opening src transaction" do
    @account.src_transactions.create!(
      user: @account.user,
      dest_account: accounts(:expense_account),
      amount_minor: -1000,
      transacted_at: Time.current,
    )

    assert_no_difference("Account.count") do
      @account.destroy
    end
  end

  test "does not destroy account with one non-opening dest transaction" do
    @account.dest_transactions.create!(
      user: @account.user,
      src_account: accounts(:revenue_account),
      amount_minor: 1000,
      transacted_at: Time.current,
    )
    @account.reload

    assert_no_difference("Account.count") do
      @account.destroy
    end
  end

  test "does not destroy account with many transactions" do
    assert_no_difference("Account.count") do
      accounts(:asset_account).destroy
    end
  end
end
