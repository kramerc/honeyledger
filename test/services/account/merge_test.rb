require "test_helper"

class Account::MergeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank = accounts(:asset_account)
    @bank_b = accounts(:linked_asset)

    @target = Account.create!(user: @user, name: "Amazon", kind: :expense, currency: @currency)
    @source = Account.create!(user: @user, name: "Amazon Marketplace", kind: :expense, currency: @currency)

    @target_txn = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @target,
      amount_minor: 300, currency: @currency, description: "Amazon", transacted_at: 2.days.ago
    )
    @source_txn = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @source,
      amount_minor: 500, currency: @currency, description: "Amazon Marketplace", transacted_at: 1.day.ago
    )
  end

  test "moves transactions from the sources onto the target" do
    service = Account::Merge.new(target: @target, sources: [ @source ], user: @user)

    assert service.call, service.errors.inspect
    assert_equal @target.id, @source_txn.reload.dest_account_id
    assert_equal @target.id, @target_txn.reload.dest_account_id
  end

  test "destroys the source accounts and keeps the target" do
    Account::Merge.new(target: @target, sources: [ @source ], user: @user).call

    assert_nil Account.find_by(id: @source.id)
    assert Account.exists?(@target.id)
  end

  test "recomputes the target balance from all moved transactions" do
    Account::Merge.new(target: @target, sources: [ @source ], user: @user).call

    assert_equal 800, @target.reload.balance_minor # 300 + 500
  end

  test "recomputes the target balance using the fx amount on the source leg" do
    revenue_target = Account.create!(user: @user, name: "Refunds", kind: :revenue, currency: @currency)
    revenue_source = Account.create!(user: @user, name: "Rebates", kind: :revenue, currency: @currency)
    transaction = Transaction.create!(
      user: @user, src_account: revenue_source, dest_account: @bank,
      amount_minor: 1000, currency: @currency, transacted_at: 1.day.ago
    )
    transaction.update_columns(fx_amount_minor: 900, fx_currency_id: currencies(:eur).id)

    Account::Merge.new(target: revenue_target, sources: [ revenue_source ], user: @user).call

    # Revenue account on the src side: balance = deposits(0) - withdrawals(COALESCE(fx, amount) = 900).
    assert_equal(-900, revenue_target.reload.balance_minor)
  end

  test "moves excluded transactions without counting them in the balance" do
    excluded = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @source,
      amount_minor: 700, currency: @currency, transacted_at: 1.day.ago
    )
    excluded.update_columns(excluded_at: Time.current)

    Account::Merge.new(target: @target, sources: [ @source ], user: @user).call

    assert_equal @target.id, excluded.reload.dest_account_id
    assert_equal 800, @target.reload.balance_minor # excluded 700 not counted
  end

  test "moves merged-away transactions so the source can be deleted" do
    master = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @bank_b,
      amount_minor: 500, currency: @currency, transacted_at: 1.day.ago
    )
    merged_away = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @source,
      amount_minor: 500, currency: @currency, transacted_at: 1.day.ago
    )
    merged_away.update!(amount_minor: 0, merged_into: master)

    assert Account::Merge.new(target: @target, sources: [ @source ], user: @user).call
    assert_nil Account.find_by(id: @source.id)
    assert_equal @target.id, merged_away.reload.dest_account_id
  end

  test "moves split parent and child transactions" do
    parent = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @source,
      amount_minor: 1000, currency: @currency, transacted_at: 1.day.ago
    )
    child = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @source,
      amount_minor: 400, currency: @currency, transacted_at: 1.day.ago, parent_transaction: parent
    )

    assert Account::Merge.new(target: @target, sources: [ @source ], user: @user).call
    assert_equal @target.id, parent.reload.dest_account_id
    assert_equal @target.id, child.reload.dest_account_id
    assert parent.split?
  end

  test "merges several sources at once" do
    other_source = Account.create!(user: @user, name: "Amazon Prime", kind: :expense, currency: @currency)
    other_txn = Transaction.create!(
      user: @user, src_account: @bank, dest_account: other_source,
      amount_minor: 200, currency: @currency, transacted_at: 1.day.ago
    )

    assert Account::Merge.new(target: @target, sources: [ @source, other_source ], user: @user).call
    assert_nil Account.find_by(id: @source.id)
    assert_nil Account.find_by(id: other_source.id)
    assert_equal @target.id, other_txn.reload.dest_account_id
    assert_equal 1000, @target.reload.balance_minor # 300 + 500 + 200
  end

  test "repoints existing import rules onto the target" do
    rule = @user.import_rules.create!(match_type: :contains, match_pattern: "marketplace", account: @source)

    Account::Merge.new(target: @target, sources: [ @source ], user: @user).call

    assert_equal @target.id, rule.reload.account_id
  end

  test "does not create new import rules" do
    assert_no_difference -> { ImportRule.count } do
      Account::Merge.new(target: @target, sources: [ @source ], user: @user).call
    end
  end

  test "rejects accounts of different kinds" do
    revenue = Account.create!(user: @user, name: "Mixed Kind", kind: :revenue, currency: @currency)

    service = Account::Merge.new(target: @target, sources: [ revenue ], user: @user)

    assert_not service.call
    assert_includes service.errors, "Only expense or revenue accounts of the same kind can be merged"
    assert Account.exists?(revenue.id)
  end

  test "rejects balance-sheet accounts" do
    service = Account::Merge.new(target: @bank, sources: [ @bank_b ], user: @user)

    assert_not service.call
    assert_includes service.errors, "Only expense or revenue accounts of the same kind can be merged"
  end

  test "rejects mismatched currencies" do
    eur_source = Account.create!(user: @user, name: "EUR Amazon", kind: :expense, currency: currencies(:eur))

    service = Account::Merge.new(target: @target, sources: [ eur_source ], user: @user)

    assert_not service.call
    assert_includes service.errors, "All accounts must use the same currency"
    assert Account.exists?(eur_source.id)
  end

  test "rejects accounts belonging to another user" do
    other = Account.create!(user: users(:two), name: "Theirs", kind: :expense, currency: @currency)

    service = Account::Merge.new(target: @target, sources: [ other ], user: @user)

    assert_not service.call
    assert_includes service.errors, "All accounts must belong to you"
  end

  test "rejects an empty source list" do
    service = Account::Merge.new(target: @target, sources: [], user: @user)

    assert_not service.call
    assert_includes service.errors, "Select at least one other account to merge"
  end

  test "rejects a missing target" do
    service = Account::Merge.new(target: nil, sources: [ @source ], user: @user)

    assert_not service.call
    assert_includes service.errors, "Select a target account to keep"
  end

  test "ignores the target when it is also passed as a source" do
    service = Account::Merge.new(target: @target, sources: [ @target, @source ], user: @user)

    assert service.call, service.errors.inspect
    assert Account.exists?(@target.id)
    assert_nil Account.find_by(id: @source.id)
  end

  test "rolls back everything when a source cannot be destroyed" do
    Account.stub_any_instance(:reset_balance, -> { raise ActiveRecord::RecordNotDestroyed.new("boom") }) do
      service = Account::Merge.new(target: @target, sources: [ @source ], user: @user)
      assert_not service.call
      assert service.errors.any?
    end

    assert_equal @source.id, @source_txn.reload.dest_account_id
    assert Account.exists?(@source.id)
  end

  test "re-importing does not resurrect a merged-away account for already-imported transactions" do
    bank = accounts(:linked_asset)
    simplefin_transaction = simplefin_transactions(:transaction_one)
    source = Account.create!(user: @user, name: "Resurrect Me", kind: :expense, currency: @currency)
    target = Account.create!(user: @user, name: "Keeper", kind: :expense, currency: @currency)

    ledger = create_sourced_transaction(
      sourceable: simplefin_transaction,
      user: @user, src_account: bank, dest_account: source,
      amount_minor: 5000, currency: @currency, description: simplefin_transaction.description,
      transacted_at: simplefin_transaction.transacted_at, synced_at: 2.days.ago
    )
    simplefin_transaction.update!(synced_at: 1.hour.ago)

    assert Account::Merge.new(target: target, sources: [ source ], user: @user).call

    assert_no_difference -> { Transaction.count } do
      Simplefin::ImportTransactionsJob.perform_now(simplefin_account_id: simplefin_transaction.account_id)
    end

    assert_equal target.id, ledger.reload.dest_account_id
    assert_nil @user.accounts.expense.find_by("LOWER(name) = LOWER(?)", "Resurrect Me")
  end
end
