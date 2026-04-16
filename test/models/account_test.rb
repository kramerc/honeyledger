require "test_helper"

class AccountTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
  end

  test "initializes balance_minor to 0 for new real accounts" do
    account = Account.new(user: users(:one), currency: currencies(:usd), kind: :asset, name: "Test")

    account.save!

    assert_equal 0, account.balance_minor
  end

  test "doesn't initialize balance_minor to 0 for new virtual accounts" do
    account = Account.new(user: users(:one), kind: :revenue, name: "Virtual", virtual: true)

    account.save!

    assert_nil account.balance_minor
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

  test "find_or_create_for_import handles RecordNotUnique" do
    user = users(:one)
    currency = currencies(:usd)

    accounts_proxy = user.accounts
    accounts_proxy.stub :find_or_create_by!, ->(_) { raise ActiveRecord::RecordNotUnique } do
      accounts_proxy.stub :find_by, @account do
        user.stub :accounts, accounts_proxy do
          assert_equal @account, Account.find_or_create_for_import(user: user, description: "Test", kind: :expense, currency: currency)
        end
      end
    end
  end

  test "find_or_create_for_import raises RecordNotUnique when both find and create fail" do
    user = users(:one)
    currency = currencies(:usd)

    accounts_proxy = user.accounts
    accounts_proxy.stub :find_or_create_by!, ->(_) { raise ActiveRecord::RecordNotUnique } do
      accounts_proxy.stub :find_by, nil do
        user.stub :accounts, accounts_proxy do
          assert_raises(ActiveRecord::RecordNotUnique) do
            Account.find_or_create_for_import(user: user, description: "Test", kind: :expense, currency: currency)
          end
        end
      end
    end
  end

  test "find_or_create_for_import preserves long descriptions" do
    user = users(:one)
    currency = currencies(:usd)
    long_description = "A" * 100

    account = Account.find_or_create_for_import(user: user, description: long_description, kind: :expense, currency: currency)

    assert_equal long_description, account.name
  end

  test "find_or_create_for_import passes description as-is" do
    user = users(:one)
    currency = currencies(:usd)

    account = Account.find_or_create_for_import(user: user, description: "  Multiple   Spaces   Store  ", kind: :expense, currency: currency)

    assert_equal "  Multiple   Spaces   Store  ", account.name
  end

  test "reset_balance recalculates balance from sum of transactions" do
    account = accounts(:asset_account)
    deposits = Transaction.where(dest_account: account).sum(:amount_minor)
    withdrawals = Transaction.where(src_account: account).sum(:amount_minor)
    expected = deposits - withdrawals

    account.update!(balance_minor: 0)
    account.reset_balance

    assert_equal expected, account.balance_minor
  end

  test "reset_balance does not recalculate balances for virtual accounts" do
    account = accounts(:opening_balance_expense)

    assert_not account.reset_balance
  end

  test "reset_balance uses fx_amount_minor for withdrawals from src account" do
    account = accounts(:eur_asset_account)
    dest = accounts(:expense_account)

    Transaction.create!(
      user: users(:one),
      category: categories(:one),
      src_account: account,
      dest_account: dest,
      amount_minor: 5000,
      fx_amount_minor: 4600,
      fx_currency: currencies(:eur),
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    account.update_column(:balance_minor, 0)
    account.reset_balance

    assert_equal(-4600, account.balance_minor)
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

  test "unlinked scope returns accounts without sourceable association" do
    unlinked = Account.unlinked

    assert_includes unlinked, accounts(:asset_account)
    assert_includes unlinked, accounts(:liability_account)
    assert_includes unlinked, accounts(:expense_account)
    assert_includes unlinked, accounts(:revenue_account)
    assert_includes unlinked, accounts(:unlinked_liability)

    assert_not_includes unlinked, accounts(:linked_asset)
    assert_not_includes unlinked, accounts(:lunchflow_linked_asset)
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

  test "balance_sheet? is true for asset accounts" do
    assert accounts(:asset_account).balance_sheet?
  end

  test "balance_sheet? is true for liability accounts" do
    assert accounts(:liability_account).balance_sheet?
  end

  test "balance_sheet? is true for equity accounts" do
    account = Account.new(kind: :equity)
    assert account.balance_sheet?
  end

  test "balance_sheet? is false for expense accounts" do
    assert_not accounts(:expense_account).balance_sheet?
  end

  test "balance_sheet? is false for revenue accounts" do
    assert_not accounts(:revenue_account).balance_sheet?
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

  test "real scope excludes virtual accounts" do
    assert_not Account.real.include?(accounts(:opening_balance_revenue))
    assert_not Account.real.include?(accounts(:opening_balance_expense))
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

  test "rejects duplicate account name within same user and kind" do
    existing = accounts(:expense_account)
    duplicate = Account.new(user: existing.user, currency: currencies(:usd), name: existing.name, kind: existing.kind)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "allows same account name with different kind" do
    existing = accounts(:expense_account)
    different_kind = Account.new(user: existing.user, currency: currencies(:usd), name: existing.name, kind: :revenue)
    assert different_kind.valid?
  end

  test "rejects reserved name for real accounts" do
    account = Account.new(user: users(:one), currency: currencies(:usd), name: "Opening Balance", kind: :asset)
    assert_not account.valid?
    assert_includes account.errors[:name], "is reserved"
  end

  test "allows reserved name for virtual accounts" do
    account = Account.new(user: users(:one), name: "Opening Balance", kind: :expense, virtual: true)
    assert account.valid?
  end

  test "rejects duplicate account name with different casing" do
    existing = accounts(:expense_account)
    duplicate = Account.new(user: existing.user, currency: currencies(:usd), name: existing.name.upcase, kind: existing.kind)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "broadcast_sidebar_replace emits a replace turbo stream targeting the account's sidebar dom id" do
    account = accounts(:asset_account)

    streams = capture_turbo_stream_broadcasts([ account.user, :sidebar ]) do
      account.broadcast_sidebar_replace
    end

    assert_equal 1, streams.size
    stream = streams.first
    assert_equal "replace", stream["action"]
    assert_equal ActionView::RecordIdentifier.dom_id(account, :sidebar), stream["target"]
    template = stream.at("template").inner_html
    assert_includes template, ActionView::RecordIdentifier.dom_id(account, :sidebar)
    assert_includes template, account.name
  end

  test "setting an opening balance broadcasts only the real account's sidebar" do
    account = Account.create!(user: users(:one), currency: currencies(:usd), name: "Brokerage", kind: :asset)
    Account.opening_balance_for(user: account.user, kind: :revenue) # ensure virtual counterpart exists

    streams = capture_turbo_stream_broadcasts([ account.user, :sidebar ]) do
      account.update!(opening_balance_amount: "100", opening_balance_transacted_at: 1.month.ago)
    end

    assert_equal 1, streams.size
    assert_equal ActionView::RecordIdentifier.dom_id(account, :sidebar), streams.first["target"]
  end

  test "changing an opening balance broadcasts the real account's sidebar" do
    account = accounts(:asset_account_with_opening_balance)

    streams = capture_turbo_stream_broadcasts([ account.user, :sidebar ]) do
      account.update!(opening_balance_amount: "999", opening_balance_transacted_at: 1.month.ago)
    end

    assert_equal 1, streams.size
    assert_equal ActionView::RecordIdentifier.dom_id(account, :sidebar), streams.first["target"]
  end

  test "clearing an opening balance broadcasts the real account's sidebar" do
    account = accounts(:asset_account_with_opening_balance)

    streams = capture_turbo_stream_broadcasts([ account.user, :sidebar ]) do
      account.update!(opening_balance_amount: "0", opening_balance_transacted_at: 1.month.ago)
    end

    assert_equal 1, streams.size
    assert_equal ActionView::RecordIdentifier.dom_id(account, :sidebar), streams.first["target"]
  end
end
