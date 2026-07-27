require "test_helper"

class Transaction::ReconcileTest < ActiveSupport::TestCase
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

    @live_simplefin_account = @ledger_account.account_sources.first.sourceable
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
    orphan = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: orphan_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
    )

    assert_equal orphan, candidate
  end

  test "returns a transaction with sourceable_id nil that matches" do
    orphan = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
    )

    assert_nil candidate
  end

  test "distinguishes an equal same-day charge/refund pair by direction (#159)" do
    # A charge (ledger on src) and a refund (ledger on dest) of the same amount
    # on the same day with the same description differ only in direction. Before
    # the directional constraint, both matched either incoming row (size == 2 →
    # nil) and a duplicate ledger transaction was created.
    charge = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )
    refund = Transaction.create!(
      user: @user, src_account: @counterpart, dest_account: @ledger_account,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    incoming_charge = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
    )
    incoming_refund = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :dest,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
    )

    assert_equal charge, incoming_charge
    assert_equal refund, incoming_refund
  end

  test "does not adopt an orphan on the opposite side from the incoming direction" do
    # Only a refund orphan exists (ledger on dest). An incoming charge
    # (ledger on src) must not adopt it — it should fall through to creating
    # a new transaction rather than mis-attaching to the refund.
    Transaction.create!(
      user: @user, src_account: @counterpart, dest_account: @ledger_account,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
    )

    assert_nil candidate
  end

  test "returns nil when no candidates match" do
    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 1.day.ago,
      description: "Nothing Like This Exists",
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
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: live_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :dest,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-24 23:30:00"),
      description: "Coffee Shop",
    )

    assert_not_nil candidate
  end

  test "does not match outside the calendar day" do
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: Time.zone.parse("2026-04-23 23:30:00")
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-24 00:30:00"),
      description: "Coffee Shop",
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
    create_sourced_transaction(
      user: other_user, src_account: other_user_account, dest_account: other_user_expense,
      amount_minor: 5000, currency: other_user_currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: other_user_stale_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
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
    orphan = create_sourced_transaction(
      user: @user, src_account: lunchflow_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: stale_lunchflow_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: lunchflow_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
    )

    assert_equal orphan, candidate
  end

  test "adopts a stale Simplefin orphan when importing a Lunchflow transaction with a prefix description" do
    full_description = "Long aggregator description that exceeds thirty-two characters by quite a lot"
    truncated_description = full_description[0, 32]

    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "stale_long_desc",
      amount: "-500.00",
      description: full_description,
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    orphan = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 50000, currency: @currency, description: full_description,
      transacted_at: 2.days.ago, sourceable: stale_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 50000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: truncated_description
    )

    assert_equal orphan, candidate
  end

  test "adopts a stale Lunchflow orphan when importing a Simplefin transaction with the longer description" do
    lunchflow_account = accounts(:lunchflow_linked_asset)
    full_description = "Recurring vendor charge with extended detail in the description"
    truncated_description = full_description[0, 32]

    stale_lunchflow_account = Lunchflow::Account.create!(
      connection: lunchflow_connections(:one),
      remote_id: 5550,
      name: "Stale LF",
      institution_name: "Test Bank",
      provider: "finicity",
      currency: "USD",
      status: "DISCONNECTED",
      balance: "1000.00"
    )
    stale_lunchflow_transaction = Lunchflow::Transaction.create!(
      account: stale_lunchflow_account,
      remote_id: "stale_truncated",
      amount: "-20.00",
      currency: "USD",
      description: "",
      merchant: truncated_description,
      pending: false,
      date: 2.days.ago.to_date
    )
    orphan = create_sourced_transaction(
      user: @user, src_account: lunchflow_account, dest_account: @counterpart,
      amount_minor: 2000, currency: @currency, description: truncated_description,
      transacted_at: 2.days.ago, sourceable: stale_lunchflow_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: lunchflow_account,
      ledger_side: :src,
      amount_minor: 2000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: full_description
    )

    assert_equal orphan, candidate
  end

  test "disambiguates between same-amount same-day transactions by description prefix (preauth vs posted)" do
    posted_description = "Posted form long description with much additional detail appended"
    preauth_description = "Preauth form long description for the same underlying charge"
    importing_description = "Posted form long description w"

    preauth_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "preauth_remote",
      amount: "-18.99",
      description: preauth_description,
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    posted_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "posted_remote",
      amount: "-18.99",
      description: posted_description,
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1899, currency: @currency, description: preauth_description,
      transacted_at: 2.days.ago, sourceable: preauth_simplefin_transaction
    )
    posted_orphan = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1899, currency: @currency, description: posted_description,
      transacted_at: 2.days.ago, sourceable: posted_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1899,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: importing_description
    )

    assert_equal posted_orphan, candidate
  end

  test "manual-entry orphans require an exact description match (rejects prefix overlap)" do
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "X",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Xtra long description from API"
    )

    assert_nil candidate
  end

  test "manual-entry orphans match case-insensitively on exact description" do
    orphan = Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Manual Entry",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "manual entry"
    )

    assert_equal orphan, candidate
  end

  test "abstains when two stale-aggregator orphans both prefix-match the importing description" do
    full_a = "Common prefix variant A with extra suffix detail"
    full_b = "Common prefix variant B with extra suffix detail"
    importing = "Common prefix variant"

    stale_a = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "stale_a",
      amount: "-500.00", description: full_a,
      transacted_at: 2.days.ago, posted: 2.days.ago
    )
    stale_b = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "stale_b",
      amount: "-500.00", description: full_b,
      transacted_at: 2.days.ago, posted: 2.days.ago
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 50000, currency: @currency, description: full_a,
      transacted_at: 2.days.ago, sourceable: stale_a
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 50000, currency: @currency, description: full_b,
      transacted_at: 2.days.ago, sourceable: stale_b
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 50000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: importing
    )

    assert_nil candidate
  end

  test "adopts a same-aggregator stale orphan whose description is a prefix of the importing description" do
    short_description = "Short stored description"
    long_description = "Short stored description with extra detail"

    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "old_short",
      amount: "-500.00",
      description: short_description,
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    orphan = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 50000, currency: @currency, description: short_description,
      transacted_at: 2.days.ago, sourceable: stale_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 50000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: long_description
    )

    assert_equal orphan, candidate
  end

  test "ignores stale aggregator transactions on the other aggregator type when belonging to a different user" do
    other_user = users(:two)
    other_user_currency = currencies(:eur)

    other_user_stale_lf_account = Lunchflow::Account.create!(
      connection: lunchflow_connections(:two),
      remote_id: 99999,
      name: "Other LF",
      institution_name: "Test Bank",
      provider: "finicity",
      currency: "EUR",
      status: "DISCONNECTED",
      balance: "1000.00"
    )
    other_user_stale_lf_transaction = Lunchflow::Transaction.create!(
      account: other_user_stale_lf_account,
      remote_id: "other_user_lf",
      amount: "-50.00",
      currency: "EUR",
      description: "",
      merchant: "Coffee Shop",
      pending: false,
      date: 2.days.ago.to_date
    )
    other_user_account = Account.create!(
      user: other_user, currency: other_user_currency, name: "Other User Bank", kind: :asset
    )
    other_user_expense = Account.create!(
      user: other_user, currency: other_user_currency, name: "Other User Coffee", kind: :expense
    )
    create_sourced_transaction(
      user: other_user, src_account: other_user_account, dest_account: other_user_expense,
      amount_minor: 5000, currency: other_user_currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: other_user_stale_lf_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop with extra detail"
    )

    assert_nil candidate
  end

  test "does not adopt a stale-aggregator orphan whose stored description is blank" do
    # The DB has no constraint preventing empty descriptions on Transaction or
    # on aggregator transactions. Without an explicit guard, the bidirectional
    # prefix predicate `LEFT(value, LENGTH(column)) = column` degenerates to
    # `'' = ''` whenever column is empty, and a single blank-description orphan
    # on the same amount/day/account would silently swallow any importing row.
    blank_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "blank_remote",
      amount: "-12.34",
      description: "",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1234, currency: @currency, description: "",
      transacted_at: 2.days.ago, sourceable: blank_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1234,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Some unrelated importing description"
    )

    assert_nil candidate
  end

  test "treats LIKE metacharacters in stored descriptions literally (no false-positive prefix match)" do
    # Stored orphan description contains `%` and `_`. If those are interpreted
    # as LIKE wildcards in the prefix-match clause, an importing description
    # whose static text happens to coincide around those positions could be
    # erroneously adopted. The shape "X%Y_Z" + a value matching that LIKE
    # pattern is the classic false-positive.
    orphan_description = "Refund 100% guaranteed_X"
    importing_description = "Refund 100abc guaranteed_X with extras"

    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "metachar_remote",
      amount: "-12.34",
      description: orphan_description,
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1234, currency: @currency, description: orphan_description,
      transacted_at: 2.days.ago, sourceable: stale_simplefin_transaction
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1234,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: importing_description
    )

    assert_nil candidate
  end

  test "skips transactions that have any live source" do
    # Live source: matches via direct sft → ledger lookup, not Reconcile.
    live_simplefin_transaction = Simplefin::Transaction.create!(
      account: @live_simplefin_account,
      remote_id: "live_with_extra",
      amount: "-50.00",
      description: "Coffee Shop",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    # A ledger transaction with two sources: one stale, one live.
    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account,
      remote_id: "stale_with_live_sibling",
      amount: "-50.00",
      description: "Coffee Shop",
      transacted_at: 2.days.ago,
      posted: 2.days.ago
    )
    ledger_transaction = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago, sourceable: stale_simplefin_transaction
    )
    TransactionSource.create!(ledger_transaction: ledger_transaction, sourceable: live_simplefin_transaction)

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "Coffee Shop"
    )

    assert_nil candidate, "ledger transactions with any live source must not be reconciliation candidates"
  end

  test "matches an aggregator-sourced orphan within the widened ±N-day window (#158)" do
    orphan_day = Time.zone.parse("2026-04-15 12:00:00")
    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "skew_orphan",
      amount: "-40.03", description: "Merchant X",
      transacted_at: orphan_day, posted: orphan_day
    )
    orphan = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 4003, currency: @currency, description: "Merchant X",
      transacted_at: orphan_day, sourceable: stale_simplefin_transaction
    )

    (-3..3).each do |offset|
      candidate = Transaction::Reconcile.call(
        ledger_account: @ledger_account,
        ledger_side: :src,
        amount_minor: 4003,
        currency_id: @currency.id,
        transacted_at: orphan_day + offset.days,
        description: "Merchant X"
      )

      assert_equal orphan, candidate, "expected a match at a #{offset}-day skew"
    end
  end

  test "does not match an aggregator-sourced orphan beyond the ±N-day window (#158)" do
    orphan_day = Time.zone.parse("2026-04-15 12:00:00")
    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "skew_orphan_far",
      amount: "-40.03", description: "Merchant X",
      transacted_at: orphan_day, posted: orphan_day
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 4003, currency: @currency, description: "Merchant X",
      transacted_at: orphan_day, sourceable: stale_simplefin_transaction
    )

    [ -4, 4 ].each do |offset|
      candidate = Transaction::Reconcile.call(
        ledger_account: @ledger_account,
        ledger_side: :src,
        amount_minor: 4003,
        currency_id: @currency.id,
        transacted_at: orphan_day + offset.days,
        description: "Merchant X"
      )

      assert_nil candidate, "expected no match at a #{offset}-day skew (N + 1)"
    end
  end

  test "abstains when two aggregator-sourced orphans fall within the widened window (#158)" do
    day_a = Time.zone.parse("2026-04-14 12:00:00")
    day_b = Time.zone.parse("2026-04-16 12:00:00")
    stale_a = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "window_amb_a",
      amount: "-40.03", description: "Merchant X",
      transacted_at: day_a, posted: day_a
    )
    stale_b = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "window_amb_b",
      amount: "-40.03", description: "Merchant X",
      transacted_at: day_b, posted: day_b
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 4003, currency: @currency, description: "Merchant X",
      transacted_at: day_a, sourceable: stale_a
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 4003, currency: @currency, description: "Merchant X",
      transacted_at: day_b, sourceable: stale_b
    )

    # Incoming date sits within ±3 days of both orphans — genuinely ambiguous.
    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 4003,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-15 12:00:00"),
      description: "Merchant X"
    )

    assert_nil candidate
  end

  test "manual-entry orphans keep the same-day window (off-by-one day is not adopted) (#117/#158)" do
    orphan_day = Time.zone.parse("2026-04-15 12:00:00")
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: "Coffee Shop",
      transacted_at: orphan_day
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: orphan_day + 1.day,
      description: "Coffee Shop"
    )

    # The widened window is aggregator-only; a manual placeholder one day off is not adopted.
    assert_nil candidate
  end

  test "attaches onto an auto-merged original whose head matches within the window (#158)" do
    bank_b = accounts(:asset_account)
    merge_day = Time.zone.parse("2026-04-15 12:00:00")

    # Aggregator A's payment on the credit card, sourced and then auto-merged with the
    # paying account's counterpart into a transfer. The original is zeroed and flagged
    # merged_into; the surviving head carries the real amount.
    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "merged_orig",
      amount: "-14.06", description: "Payment Credit",
      transacted_at: merge_day, posted: merge_day
    )
    original = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1406, currency: @currency, description: "Payment Credit",
      transacted_at: merge_day, sourceable: stale_simplefin_transaction
    )
    counterpart_side = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
      amount_minor: 1406, currency: @currency, description: "Payment Credit",
      transacted_at: merge_day
    )
    merger = Transaction::Merge.new(original, counterpart_side, user: @user)
    assert merger.call, merger.errors.inspect
    head = merger.merged_transaction

    # Aggregator B's copy of the same payment arrives one day off.
    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1406,
      currency_id: @currency.id,
      transacted_at: merge_day + 1.day,
      description: "Payment Credit"
    )

    assert_equal original, candidate
    assert_equal head.id, candidate.merged_into_id
  end

  test "abstains when two auto-merged originals match within the window (#158)" do
    bank_b = accounts(:asset_account)

    [ Time.zone.parse("2026-04-14 12:00:00"), Time.zone.parse("2026-04-16 12:00:00") ].each_with_index do |day, index|
      stale = Simplefin::Transaction.create!(
        account: @stale_simplefin_account, remote_id: "merged_amb_#{index}",
        amount: "-14.06", description: "Payment Credit",
        transacted_at: day, posted: day
      )
      original = create_sourced_transaction(
        user: @user, src_account: @ledger_account, dest_account: @counterpart,
        amount_minor: 1406, currency: @currency, description: "Payment Credit",
        transacted_at: day, sourceable: stale
      )
      counterpart_side = Transaction.create!(
        user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
        amount_minor: 1406, currency: @currency, description: "Payment Credit",
        transacted_at: day
      )
      assert Transaction::Merge.new(original, counterpart_side, user: @user).call
    end

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1406,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-15 12:00:00"),
      description: "Payment Credit"
    )

    assert_nil candidate
  end

  test "abstains when a live orphan and a merged original both match within the window (#158)" do
    bank_b = accounts(:asset_account)

    # A live aggregator orphan two days before the incoming date.
    live_day = Time.zone.parse("2026-04-14 12:00:00")
    stale_live = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "collide_live",
      amount: "-14.06", description: "Payment Credit",
      transacted_at: live_day, posted: live_day
    )
    create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1406, currency: @currency, description: "Payment Credit",
      transacted_at: live_day, sourceable: stale_live
    )

    # An auto-merged original two days after the incoming date, whose head matches.
    merged_day = Time.zone.parse("2026-04-16 12:00:00")
    stale_merged = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "collide_merged",
      amount: "-14.06", description: "Payment Credit",
      transacted_at: merged_day, posted: merged_day
    )
    original = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1406, currency: @currency, description: "Payment Credit",
      transacted_at: merged_day, sourceable: stale_merged
    )
    counterpart_side = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
      amount_minor: 1406, currency: @currency, description: "Payment Credit",
      transacted_at: merged_day
    )
    assert Transaction::Merge.new(original, counterpart_side, user: @user).call

    # Both a live and a merged candidate sit within ±3 days — genuinely ambiguous,
    # so we must not silently attach to the live one and hide the merged event.
    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1406,
      currency_id: @currency.id,
      transacted_at: Time.zone.parse("2026-04-15 12:00:00"),
      description: "Payment Credit"
    )

    assert_nil candidate
  end

  test "CSV-sourced orphans keep the same-day window (the widening is aggregator-only) (#158)" do
    orphan_day = Time.zone.parse("2026-04-15 12:00:00")
    csv_orphan = create_csv_sourced_orphan(transacted_at: orphan_day, description: "Merchant X with extra detail")

    # Same day, prefix match → adopted (the prefix branch still applies to CSV).
    same_day = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: orphan_day,
      description: "Merchant X"
    )
    assert_equal csv_orphan, same_day

    # One day off → not adopted. CSV sources do not get the widened window.
    off_by_one = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: orphan_day + 1.day,
      description: "Merchant X"
    )
    assert_nil off_by_one
  end

  test "adopts a stale orphan whose description masks the account digits (#221)" do
    orphan_description = "TRANSFER FROM LINKED ACCOUNT VS. AXX-XXX123-4 (Cash)"
    importing_description = "TRANSFER FROM LINKED ACCOUNT VS. A01-234123-4 (Cash)"

    orphan = create_aggregator_orphan(remote_id: "masked_account", description: orphan_description)

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: importing_description
    )

    # Masking is mid-string, so neither description is a prefix of the other; only the
    # normalized comparison can reach this row.
    assert_equal orphan, candidate
  end

  test "adopts a stale orphan whose description masks an embedded date (#221)" do
    orphan = create_aggregator_orphan(
      remote_id: "masked_date",
      description: "PAYMENT TO LENDER as of XXXX-07-03 (Cash)"
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "PAYMENT TO LENDER as of 2026-07-03 (Cash)"
    )

    assert_equal orphan, candidate
  end

  test "abstains when two orphans differ only in their masked digits (#221)" do
    # The over-normalization failure mode: collapsing digit runs makes two genuinely
    # distinct transfers look alike. Reconcile must abstain and leave a duplicate rather
    # than attach the incoming row to an arbitrary one of them.
    create_aggregator_orphan(remote_id: "masked_amb_a", description: "TRANSFER TO SAVINGS VS. A01-234123-4 (Cash)")
    create_aggregator_orphan(remote_id: "masked_amb_b", description: "TRANSFER TO SAVINGS VS. A99-887766-4 (Cash)")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "TRANSFER TO SAVINGS VS. AXX-XXXXXX-4 (Cash)"
    )

    assert_nil candidate
  end

  test "does not normalize when neither description is masked (#221)" do
    # The ambiguity guard cannot help here: there is exactly one candidate, so an unguarded
    # normalization would collapse two genuinely distinct account numbers to the same string
    # and attach the incoming source to the wrong ledger event. Both sides report their digits
    # verbatim, so there is no mask to bridge and the raw comparison must have the last word.
    create_aggregator_orphan(remote_id: "unmasked_digits", description: "TRANSFER TO SAVINGS VS. A01-234123-4 (Cash)")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "TRANSFER TO SAVINGS VS. A99-887766-4 (Cash)"
    )

    assert_nil candidate
  end

  test "manual-entry orphans are not reached by masked-digit normalization (#221)" do
    # #117: a manual placeholder keeps its exact-description rule, so it cannot be scooped
    # up by an aggregator row that differs only in an account number.
    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency,
      description: "PAYMENT TO LENDER as of XXXX-07-03 (Cash)",
      transacted_at: 2.days.ago
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "PAYMENT TO LENDER as of 2026-07-03 (Cash)"
    )

    assert_nil candidate
  end

  test "does not normalize away a single differing digit (#221)" do
    # Runs of one are left alone, so a lone digit still distinguishes two descriptions.
    create_aggregator_orphan(remote_id: "single_digit", description: "PAYMENT 1")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "PAYMENT 2"
    )

    assert_nil candidate
  end

  test "keeps the raw prefix match for truncations that land mid-digit-run (#221)" do
    # "VENDOR CHARGE 1" is a raw prefix of the importing description but normalizes to
    # "vendor charge 1" against "vendor charge ~ extra detail", which is not a prefix.
    # Only the raw branch reaches this row — it would regress if normalization replaced
    # the prefix match instead of being OR'd onto it.
    orphan = create_aggregator_orphan(remote_id: "truncated_run", description: "VENDOR CHARGE 1")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "VENDOR CHARGE 12 EXTRA DETAIL"
    )

    assert_equal orphan, candidate
  end

  test "treats a literal hash in a description as distinguishing, not as a mask (#221)" do
    # `#` is a store-number marker in real feeds, not a redaction glyph, so it stays
    # outside the maskable class — and it is not the placeholder either, which is what
    # keeps "STORE #12" from normalizing onto "STORE 12".
    create_aggregator_orphan(remote_id: "literal_hash", description: "STORE #12 PURCHASE")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "STORE 12 PURCHASE"
    )

    assert_nil candidate
  end

  test "treats regex metacharacters in the importing description literally (#221)" do
    # If the importing value were ever interpolated into the normalization pattern, this
    # shape would match the stored description as a regex. It must compare as literal text.
    create_aggregator_orphan(remote_id: "regex_metachar", description: "PROMO BIG SALE")

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: 2.days.ago,
      description: "PROMO .* SALE"
    )

    assert_nil candidate
  end

  test "attaches a masked-digit variant onto an auto-merged original (#221)" do
    bank_b = accounts(:asset_account)
    merge_day = Time.zone.parse("2026-04-15 12:00:00")
    orphan_description = "TRANSFER FROM LINKED ACCOUNT VS. AXX-XXX123-4 (Cash)"

    stale_simplefin_transaction = Simplefin::Transaction.create!(
      account: @stale_simplefin_account, remote_id: "masked_merged_orig",
      amount: "-14.06", description: orphan_description,
      transacted_at: merge_day, posted: merge_day
    )
    original = create_sourced_transaction(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 1406, currency: @currency, description: orphan_description,
      transacted_at: merge_day, sourceable: stale_simplefin_transaction
    )
    counterpart_side = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
      amount_minor: 1406, currency: @currency, description: orphan_description,
      transacted_at: merge_day
    )
    merger = Transaction::Merge.new(original, counterpart_side, user: @user)
    assert merger.call, merger.errors.inspect
    head = merger.merged_transaction

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 1406,
      currency_id: @currency.id,
      transacted_at: merge_day,
      description: "TRANSFER FROM LINKED ACCOUNT VS. A01-234123-4 (Cash)"
    )

    assert_equal original, candidate
    assert_equal head.id, candidate.merged_into_id
  end

  test "adopts the strictly nearest candidate when several match (#197)" do
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")
    description = "RECURRING VENDOR CHARGE"

    nearest = create_aggregator_orphan(
      remote_id: "tiebreak_near", description: description, transacted_at: incoming_day - 1.day
    )
    create_aggregator_orphan(
      remote_id: "tiebreak_far", description: description, transacted_at: incoming_day - 3.days
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: description
    )

    assert_equal nearest, candidate
  end

  test "abstains when two candidates are equidistant (#197)" do
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")
    description = "RECURRING VENDOR CHARGE"

    create_aggregator_orphan(
      remote_id: "equi_before", description: description, transacted_at: incoming_day - 1.day
    )
    create_aggregator_orphan(
      remote_id: "equi_after", description: description, transacted_at: incoming_day + 1.day
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: description
    )

    assert_nil candidate
  end

  test "measures distance in calendar days rather than raw timestamps (#197)" do
    # Lunch Flow stores a DATE, so its ledger rows sit at midnight, while an incoming SimpleFIN
    # row carries a real posted time. An afternoon incoming row is fewer *hours* from the next
    # day's midnight than from its own day's, so timestamp distance would pick the wrong day.
    incoming_day = Time.zone.parse("2026-04-15 14:00:00")

    same_day = create_aggregator_orphan(
      remote_id: "granularity_same_day", description: "RECURRING VENDOR CHARGE",
      transacted_at: Time.zone.parse("2026-04-15 00:00:00")
    )
    create_aggregator_orphan(
      remote_id: "granularity_next_day", description: "RECURRING VENDOR CHARGE",
      transacted_at: Time.zone.parse("2026-04-16 00:00:00")
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: "RECURRING VENDOR CHARGE"
    )

    assert_equal same_day, candidate
  end

  test "abstains for a same-day cluster at differing times (#197)" do
    # Same calendar day means equidistant, so the cluster stays as ambiguous as it was before
    # the tie-break existed.
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")

    create_aggregator_orphan(
      remote_id: "cluster_early", description: "RECURRING VENDOR CHARGE",
      transacted_at: Time.zone.parse("2026-04-15 01:00:00")
    )
    create_aggregator_orphan(
      remote_id: "cluster_late", description: "RECURRING VENDOR CHARGE",
      transacted_at: Time.zone.parse("2026-04-15 05:00:00")
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: "RECURRING VENDOR CHARGE"
    )

    assert_nil candidate
  end

  test "abstains when a manual entry is in the running, even as the nearest (#197)" do
    # Adopting a hand-entered row on date proximity alone is a call for a human to confirm, so
    # the pair goes to the suggestion surface (#223) rather than being attached here.
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")
    description = "RECURRING VENDOR CHARGE"

    Transaction.create!(
      user: @user, src_account: @ledger_account, dest_account: @counterpart,
      amount_minor: 5000, currency: @currency, description: description,
      transacted_at: incoming_day
    )
    create_aggregator_orphan(
      remote_id: "manual_competitor", description: description, transacted_at: incoming_day + 2.days
    )

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: description
    )

    assert_nil candidate
  end

  test "abstains when a live orphan and a merged original sit at different distances (#158/#197)" do
    # The #158 carve-out: date proximity must not resolve this shape, because hiding a merged
    # event is a different kind of damage from picking the wrong one of two equals. The existing
    # #158 test is equidistant and so cannot detect a regression here.
    bank_b = accounts(:asset_account)
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")
    description = "RECURRING VENDOR CHARGE"

    create_aggregator_orphan(
      remote_id: "distance_live", description: description, transacted_at: incoming_day
    )

    merged_day = incoming_day + 2.days
    original = create_aggregator_orphan(
      remote_id: "distance_merged", description: description, transacted_at: merged_day
    )
    counterpart_side = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: bank_b,
      amount_minor: 5000, currency: @currency, description: description,
      transacted_at: merged_day
    )
    assert Transaction::Merge.new(original, counterpart_side, user: @user).call

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: description
    )

    assert_nil candidate
  end

  test "abstains when the candidate set fills the tie-break fetch limit (#197)" do
    # One candidate is uniquely nearest, so without the cap guard the tie-break would attach.
    # At this much ambiguity we cannot be sure the true nearest was even fetched.
    incoming_day = Time.zone.parse("2026-04-15 12:00:00")
    description = "RECURRING VENDOR CHARGE"

    create_aggregator_orphan(
      remote_id: "cap_nearest", description: description, transacted_at: incoming_day
    )
    (Transaction::Reconcile::RECONCILE_TIE_BREAK_CANDIDATE_LIMIT - 1).times do |index|
      create_aggregator_orphan(
        remote_id: "cap_filler_#{index}", description: description,
        transacted_at: incoming_day + 2.days
      )
    end

    candidate = Transaction::Reconcile.call(
      ledger_account: @ledger_account,
      ledger_side: :src,
      amount_minor: 5000,
      currency_id: @currency.id,
      transacted_at: incoming_day,
      description: description
    )

    assert_nil candidate
  end

  test "pairs each of two incoming rows with its own same-day candidate (#197)" do
    # The shape observed on a live account: two equal-amount charges on consecutive days, each
    # reported by both aggregators. Counting candidates abstains on both; proximity resolves a
    # clean 1:1 pairing.
    first_day = Time.zone.parse("2026-04-15 12:00:00")
    second_day = first_day + 1.day
    description = "RECURRING VENDOR CHARGE"

    first_orphan = create_aggregator_orphan(
      remote_id: "pairing_first", description: description, transacted_at: first_day
    )
    second_orphan = create_aggregator_orphan(
      remote_id: "pairing_second", description: description, transacted_at: second_day
    )

    reconcile_on = ->(day) do
      Transaction::Reconcile.call(
        ledger_account: @ledger_account,
        ledger_side: :src,
        amount_minor: 5000,
        currency_id: @currency.id,
        transacted_at: day,
        description: description
      )
    end

    assert_equal first_orphan, reconcile_on.call(first_day)
    assert_equal second_orphan, reconcile_on.call(second_day)
  end

  private

    def create_aggregator_orphan(remote_id:, description:, amount_minor: 5000, transacted_at: 2.days.ago)
      # Derive the aggregator amount from amount_minor rather than hard-coding it, so a caller
      # that varies amount_minor cannot silently create a source/ledger amount mismatch.
      source_amount = -(amount_minor.to_d / 10**@currency.decimal_places)

      stale_simplefin_transaction = Simplefin::Transaction.create!(
        account: @stale_simplefin_account, remote_id: remote_id,
        amount: source_amount.to_s("F"), description: description,
        transacted_at: transacted_at, posted: transacted_at
      )

      create_sourced_transaction(
        user: @user, src_account: @ledger_account, dest_account: @counterpart,
        amount_minor: amount_minor, currency: @currency, description: description,
        transacted_at: transacted_at, sourceable: stale_simplefin_transaction
      )
    end

    def create_csv_sourced_orphan(transacted_at:, description:, amount_minor: 5000)
      import = Csv::Import.new(user: @user, account: @ledger_account, state: "imported")
      import.file.attach(
        io: StringIO.new("date,amount\n2026-01-01,-50.00\n"),
        filename: "import.csv",
        content_type: "text/csv"
      )
      import.save!

      csv_transaction = Csv::Transaction.create!(
        import: import, row_index: 0, amount_minor: -amount_minor,
        description: description, transacted_at: transacted_at
      )

      create_sourced_transaction(
        user: @user, src_account: @ledger_account, dest_account: @counterpart,
        amount_minor: amount_minor, currency: @currency, description: description,
        transacted_at: transacted_at, sourceable: csv_transaction
      )
    end
end
