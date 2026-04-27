require "test_helper"

class Transaction::AdoptOrphanTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @ledger_account = accounts(:linked_asset)
    @counterpart = accounts(:expense_account)

    @stale_simplefin_account = Simplefin::Account.create!(
      connection: simplefin_connections(:one),
      remote_id: "stale_acc_1",
      name: "Stale Bank",
      currency: "USD",
      balance: "1000.00"
    )

    @live_simplefin_account = @ledger_account.sourceable
  end

  test "returns the single matching orphan whose sourceable is on an unlinked aggregator account" do
    orphan_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "old_remote",
      amount: "-50.00",
      description: "Coffee Shop",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    orphan = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: orphan_simplefin_transaction
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_equal orphan, candidate
  end

  test "returns a transaction with sourceable_id nil that matches" do
    orphan = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_equal orphan, candidate
  end

  test "returns nil when multiple candidates match" do
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 1.day.ago.beginning_of_day + 1.hour
    )
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 1.day.ago.beginning_of_day + 5.hours
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "returns nil when no candidates match" do
    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 1.day.ago,
      description: "Nothing Like This Exists",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores ledger transactions sourced from a still-linked aggregator account" do
    live_simplefin_transaction = Simplefin::Transaction.create!(
      account: @live_simplefin_account,
      remote_id: "live_remote",
      amount: "-50.00",
      description: "Coffee Shop",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: live_simplefin_transaction
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores ledger transactions on a different ledger account" do
    other_ledger_account = accounts(:asset_account)
    Transaction.create!(
      user: @user, src_account: other_ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores opening balance transactions" do
    opening_balance_revenue = Account.create!(
      user: @user, currency: @currency, name: "Opening Balance", kind: :revenue, virtual: true
    )
    Transaction.create!(
      user: @user, src_account: opening_balance_revenue, dest_account: @ledger_account,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, opening_balance: true
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores merged-into transactions and AutoMerge synthetic results" do
    bank_b = accounts(:asset_account)

    expense_orphan = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )
    revenue_orphan = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    merger = Transaction::Merge.new(expense_orphan, revenue_orphan, user: @user)
    assert merger.call, merger.errors.inspect

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    # The originals are zeroed (amount_minor=0, merged_into populated) and the synthetic
    # has merged_sources populated. None should be adoptable.
    assert_nil candidate
  end

  test "ignores split parents and split children" do
    parent = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, split: true
    )
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, parent_transaction_id: parent.id
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores FX transactions" do
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago,
      fx_amount_minor: 4500, fx_currency: currencies(:eur)
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "matches across calendar day with different times" do
    target_day = Time.zone.parse("2026-04-24 02:00:00")
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: target_day
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-24 23:30:00"),
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_not_nil candidate
  end

  test "does not match outside the calendar day" do
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: Time.zone.parse("2026-04-23 23:30:00")
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-24 00:30:00"),
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "ignores stale aggregator transactions belonging to a different user" do
    # Another user has a stale Simplefin::Account with a transaction whose amount, day, and
    # description happen to match. Their data must not pollute the current user's candidate set.
    other_user = users(:two)
    other_user_currency = currencies(:eur)

    other_user_stale_simplefin_account = Simplefin::Account.create!(
      connection: simplefin_connections(:two),
      remote_id: "other_user_stale",
      name: "Other User Stale Account",
      currency: "EUR",
      balance: "1000.00"
    )
    other_user_stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: other_user_stale_simplefin_account,
      remote_id: "other_user_old_remote",
      amount: "-50.00",
      description: "Coffee Shop",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    other_user_account = Account.create!(
      user: other_user, currency: other_user_currency, name: "Other User Bank", kind: :asset
    )
    other_user_expense = Account.create!(
      user: other_user, currency: other_user_currency, name: "Other User Coffee", kind: :expense
    )
    Transaction.create!(
      user: other_user, src_account: other_user_account, dest_account: other_user_expense,
      amount_minor: 5000, currency: other_user_currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: other_user_stale_simplefin_transaction
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: @ledger_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Simplefin::Transaction",
      aggregator_account_class: Simplefin::Account
    )

    assert_nil candidate
  end

  test "works for Lunchflow aggregator" do
    lunchflow_account = accounts(:lunchflow_linked_asset)

    stale_lunchflow_account = Lunchflow::Account.create!(
      connection: lunchflow_connections(:one),
      remote_id: 999,
      name: "Stale LF Account",
      institution_name: "Test Bank",
      provider: "finicity",
      currency: "USD",
      status: "DISCONNECTED",
      balance: "1000.00"
    )
    stale_lunchflow_transaction = Lunchflow::Transaction.create!(
      account: stale_lunchflow_account,
      remote_id: "old_lf_remote",
      amount: "-50.00",
      currency: "USD",
      description: "Coffee Shop",
      pending: false,
      date: 2.days.ago.to_date
    )
    orphan = Transaction.create!(
      user: @user, src_account: lunchflow_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: stale_lunchflow_transaction
    )

    candidate = Transaction::AdoptOrphan.call(
      ledger_account: lunchflow_account,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      sourceable_type: "Lunchflow::Transaction",
      aggregator_account_class: Lunchflow::Account
    )

    assert_equal orphan, candidate
  end
end
