require "test_helper"

class Transaction::DeduplicateTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @category = categories(:one)

    # A fresh bank account so balance assertions are isolated from fixtures.
    @bank = Account.create!(user: @user, name: "Dedupe Bank", kind: :asset, currency: @currency)
    @expense_a = Account.create!(user: @user, name: "Coffee Shop", kind: :expense, currency: @currency)
    @expense_b = Account.create!(user: @user, name: "Coffee Shop (alt)", kind: :expense, currency: @currency)

    @charge_a = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "Coffee Shop",
      transacted_at: 2.days.ago
    )
    @charge_b = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_b,
      amount_minor: 500, currency: @currency, description: "COFFEE SHOP LLC",
      transacted_at: 1.day.ago
    )
  end

  test "combines two duplicate charges into one surviving row" do
    assert_difference "Transaction.count", -1 do
      service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
      assert service.call, service.errors.inspect
    end

    assert Transaction.exists?(@charge_a.id)
    assert_not Transaction.exists?(@charge_b.id)
  end

  test "counts the event once on the bank account" do
    # Two charges of 500 double-count the bank to -1000.
    assert_equal(-1000, @bank.reload.balance_minor)

    Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user).call

    assert_equal(-500, @bank.reload.balance_minor)
  end

  test "moves the loser's sources onto the survivor" do
    sourced = create_sourced_transaction(
      user: @user, src_account: @bank, dest_account: @expense_b,
      amount_minor: 500, currency: @currency, description: "Imported coffee",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    # Keep @charge_a; the imported row's source should move onto it.
    service = Transaction::Deduplicate.new(@charge_a, sourced, user: @user, survivor: @charge_a)
    assert service.call, service.errors.inspect

    @charge_a.reload
    assert_equal [ simplefin_transactions(:transaction_one) ], @charge_a.transaction_sources.map(&:sourceable)
    assert_not Transaction.exists?(sourced.id)
  end

  test "collapses three duplicates" do
    charge_c = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "Coffee again",
      transacted_at: 3.days.ago
    )

    assert_difference "Transaction.count", -2 do
      service = Transaction::Deduplicate.new(@charge_a, @charge_b, charge_c, user: @user)
      assert service.call, service.errors.inspect
    end
  end

  test "honors an explicit survivor even when it is not the heuristic default" do
    # @charge_b is newer, so the heuristic would prefer @charge_a; override it.
    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user, survivor: @charge_b)
    assert service.call

    assert_equal @charge_b.id, service.survivor.id
    assert Transaction.exists?(@charge_b.id)
    assert_not Transaction.exists?(@charge_a.id)
  end

  test "heuristic prefers a categorized row when no survivor is given" do
    @charge_b.update!(category: @category)

    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
    assert service.call

    assert_equal @charge_b.id, service.survivor.id
  end

  test "heuristic tie-breaks on the oldest row" do
    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
    assert service.call

    # @charge_a is older (2 days vs 1 day ago) and neither is categorized.
    assert_equal @charge_a.id, service.survivor.id
  end

  test "rejects a survivor that is not among the selected transactions" do
    other = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "Other",
      transacted_at: 1.day.ago
    )

    assert_no_difference "Transaction.count" do
      service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user, survivor: other)
      assert_not service.call
      assert_includes service.errors.join, "keep"
    end
  end

  test "keeps a manual categorized row and preserves the imported source" do
    manual = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "Manual coffee",
      transacted_at: 1.day.ago, category: @category
    )
    imported = create_sourced_transaction(
      user: @user, src_account: @bank, dest_account: @expense_b,
      amount_minor: 500, currency: @currency, description: "SQ *COFFEE",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )

    service = Transaction::Deduplicate.new(manual, imported, user: @user)
    assert service.call

    assert_equal manual.id, service.survivor.id
    assert_equal [ simplefin_transactions(:transaction_one) ], manual.reload.transaction_sources.map(&:sourceable)
  end

  test "rejects fewer than two transactions" do
    service = Transaction::Deduplicate.new(@charge_a, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "at least two"
  end

  test "rejects mismatched amounts" do
    @charge_b.update!(amount_minor: 600)
    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "Amounts"
  end

  test "combines two refunds posted to the bank" do
    revenue = Account.create!(user: @user, name: "Refund Source", kind: :revenue, currency: @currency)
    refund_a = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank,
      amount_minor: 500, currency: @currency, description: "Refund", transacted_at: 2.days.ago
    )
    refund_b = Transaction.create!(
      user: @user, src_account: revenue, dest_account: @bank,
      amount_minor: 500, currency: @currency, description: "REFUND", transacted_at: 1.day.ago
    )

    assert_difference "Transaction.count", -1 do
      service = Transaction::Deduplicate.new(refund_a, refund_b, user: @user)
      assert service.call, service.errors.inspect
    end
  end

  test "rejects mismatched currencies" do
    # Currency is derived from the dest account, so an EUR expense account on the
    # same bank yields a differing currency without changing the bank/side.
    eur_expense = Account.create!(user: @user, name: "EUR Expense", kind: :expense, currency: currencies(:eur))
    eur_charge = Transaction.create!(
      user: @user, src_account: @bank, dest_account: eur_expense,
      amount_minor: 500, description: "EUR charge", transacted_at: 1.day.ago
    )
    assert_equal currencies(:eur), eur_charge.currency

    service = Transaction::Deduplicate.new(@charge_a, eur_charge, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "Currencies"
  end

  test "rejects foreign exchange transactions" do
    fx_charge = Transaction.create!(
      user: @user, src_account: @bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "FX charge",
      transacted_at: 1.day.ago, fx_amount_minor: 400, fx_currency: currencies(:eur)
    )
    service = Transaction::Deduplicate.new(@charge_a, fx_charge, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "Foreign exchange"
  end

  test "rejects split transactions" do
    @charge_b.update_columns(split: true)
    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "Split"
  end

  test "rescues a RecordInvalid raised while applying the change" do
    @charge_b.stub(:destroy!, ->(*) { raise ActiveRecord::RecordInvalid.new(@charge_b) }) do
      service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user, survivor: @charge_a)
      assert_not service.call
      assert service.errors.any?
    end
  end

  test "rejects different bank accounts" do
    other_bank = Account.create!(user: @user, name: "Other Bank", kind: :asset, currency: @currency)
    other = Transaction.create!(
      user: @user, src_account: other_bank, dest_account: @expense_a,
      amount_minor: 500, currency: @currency, description: "Other bank charge",
      transacted_at: 1.day.ago
    )
    service = Transaction::Deduplicate.new(@charge_a, other, user: @user)
    assert_not service.call
    assert_includes service.errors.join, "same bank account"
  end

  test "rejects opposite sides on the same account" do
    refund = Transaction.create!(
      user: @user, src_account: @expense_a, dest_account: @bank,
      amount_minor: 500, currency: @currency, description: "Refund",
      transacted_at: 1.day.ago
    )
    service = Transaction::Deduplicate.new(@charge_a, refund, user: @user)
    assert_not service.call
  end

  test "rejects transfers" do
    other_bank = Account.create!(user: @user, name: "Transfer Bank", kind: :asset, currency: @currency)
    transfer = Transaction.create!(
      user: @user, src_account: @bank, dest_account: other_bank,
      amount_minor: 500, currency: @currency, description: "Transfer",
      transacted_at: 1.day.ago
    )
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
    assert_not service.call
  end

  test "rejects excluded transactions" do
    sourced = create_sourced_transaction(
      user: @user, src_account: @bank, dest_account: @expense_b,
      amount_minor: 500, currency: @currency, description: "Imported",
      transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
    )
    Transaction::Exclude.new(sourced, user: @user).call

    service = Transaction::Deduplicate.new(@charge_a, sourced, user: @user)
    assert_not service.call
  end

  test "rejects merged transactions" do
    @charge_b.update_columns(merged_into_id: @charge_a.id)
    service = Transaction::Deduplicate.new(@charge_a, @charge_b, user: @user)
    assert_not service.call
  end

  test "rejects transactions belonging to another user" do
    others = transactions(:opening_balance_revenue)
    service = Transaction::Deduplicate.new(@charge_a, others, user: @user)
    assert_not service.call
  end
end
