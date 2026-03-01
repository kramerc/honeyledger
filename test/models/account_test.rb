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
    @account.opening_balance_transaction_attributes = { amount_minor: 1000, transacted_at: 1.month.ago }

    @account.save!

    assert_not_nil @account.opening_balance_transaction
    assert_equal 1, @account.dest_transactions.count
    assert @account.empty?
  end

  test "real? is true if account is not virtual" do
    assert @account.real?
  end

  test "real? is false if account is virtual" do
    @account.update!(virtual: true)

    assert_not @account.real?
  end

  test "account is valid if opening_balance_transaction.amount is blank" do
    @account.opening_balance_transaction_attributes = { amount: "", transacted_at: 1.month.ago }

    assert @account.valid?
  end

  test "account is valid if opening_balance_transaction.amount is zero" do
    @account.opening_balance_transaction_attributes = { amount: 0, transacted_at: 1.month.ago }

    assert @account.valid?
  end

  test "account is invalid if opening_balance_transaction.amount is not a number" do
    @account.opening_balance_transaction_attributes = { amount: "invalid", transacted_at: 1.month.ago }

    assert @account.invalid?
    assert_includes @account.errors["opening_balance_transaction.amount"], "is not a number"
  end

  test "account is valid if opening_balance_transaction.amount_minor is blank" do
    @account.opening_balance_transaction_attributes = { amount_minor: "", transacted_at: 1.month.ago }

    assert @account.valid?
  end

  test "account is valid if opening_balance_transaction.amount_minor is zero" do
    @account.opening_balance_transaction_attributes = { amount_minor: 0, transacted_at: 1.month.ago }

    assert @account.valid?
  end

  test "account is invalid if opening_balance_transaction.amount_minor is not a number" do
    @account.opening_balance_transaction_attributes = { amount_minor: "invalid", transacted_at: 1.month.ago }

    assert @account.invalid?
    assert_includes @account.errors["opening_balance_transaction.amount_minor"], "is not a number"
  end

  test "account is invalid if opening_balance_transaction.transacted_at is invalid" do
    @account.opening_balance_transaction_attributes = { amount: 1, transacted_at: nil }

    assert @account.invalid?
    assert_includes @account.errors["opening_balance_transaction.transacted_at"], "can't be blank"
  end

  test "opening balance transaction is saved on account save" do
    @account.opening_balance_transaction_attributes = { amount: 1, transacted_at: 1.month.ago }
    assert @account.opening_balance_transaction.new_record?

    @account.save!

    assert @account.opening_balance_transaction.persisted?
  end

  test "opening balance transaction is destroyed if amount is blank" do
    @account.opening_balance_transaction_attributes = { amount: 1, transacted_at: 1.month.ago }

    @account.save!

    @account.opening_balance_transaction_attributes = { amount: "", transacted_at: 1.month.ago }

    assert_difference("Transaction.count", -1) do
      @account.save!
    end
  end

  test "opening balance transaction is destroyed if amount is zero" do
    @account.opening_balance_transaction_attributes = { amount: 1, transacted_at: 1.month.ago }

    @account.save!

    @account.opening_balance_transaction_attributes = { amount: 0, transacted_at: 1.month.ago }

    assert_difference("Transaction.count", -1) do
      @account.save!
    end
  end

  test "opening balance transaction is destroyed if amount_minor is blank" do
    @account.opening_balance_transaction_attributes = { amount_minor: 1, transacted_at: 1.month.ago }

    @account.save!

    @account.opening_balance_transaction_attributes = { amount_minor: "", transacted_at: 1.month.ago }

    assert_difference("Transaction.count", -1) do
      @account.save!
    end
  end

  test "opening balance transaction is destroyed if amount_minor is zero" do
    @account.opening_balance_transaction_attributes = { amount_minor: 1, transacted_at: 1.month.ago }

    @account.save!

    @account.opening_balance_transaction_attributes = { amount_minor: 0, transacted_at: 1.month.ago }

    assert_difference("Transaction.count", -1) do
      @account.save!
    end
  end

  test "destroys account with only a revenue opening balance transaction" do
    transaction = Transaction.create!(
      user: @account.user,
      currency: @account.currency,
      amount_minor: 1000,
      transacted_at: Time.current,
      opening_balance: true,
      opening_balance_target_account: @account
    )

    assert_difference("Account.count", -1) do
      @account.destroy
    end

    assert_raises(ActiveRecord::RecordNotFound) { transaction.reload }
  end

  test "destroys account with only a expense opening balance transaction" do
    transaction = Transaction.create!(
      user: @account.user,
      currency: @account.currency,
      amount_minor: -1000,
      transacted_at: Time.current,
      opening_balance: true,
      opening_balance_target_account: @account
    )

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
