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
    @other_bank = Account.create!(user: @user, name: "Transfer Bank", kind: :asset, currency: @currency)

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

  test "absorbs a one-sided duplicate into a plain transfer, keeping the transfer" do
    transfer = plain_transfer

    assert_difference "Transaction.count", -1 do
      service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
      assert service.call, service.errors.inspect
      assert_equal transfer, service.survivor
    end

    assert Transaction.exists?(transfer.id)
    assert_not Transaction.exists?(@charge_a.id)
  end

  test "moves the loser's sources onto a plain transfer itself" do
    transfer = plain_transfer
    sourced = sourced_duplicate(simplefin_transactions(:transaction_one))

    service = Transaction::Deduplicate.new(sourced, transfer, user: @user)
    assert service.call, service.errors.inspect

    assert_equal [ simplefin_transactions(:transaction_one) ], transfer.reload.transaction_sources.map(&:sourceable)
  end

  test "absorbs a one-sided duplicate into a merged transfer, keeping the transfer" do
    transfer = merged_transfer

    assert_difference "Transaction.count", -1 do
      service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
      assert service.call, service.errors.inspect
      assert_equal transfer, service.survivor
    end

    assert Transaction.exists?(transfer.id)
    assert_not Transaction.exists?(@charge_a.id)
    assert_equal 2, transfer.reload.merged_sources.count
  end

  test "parks the loser's sources on the merged origin that shares the bank side" do
    transfer = merged_transfer
    sourced = sourced_duplicate(simplefin_transactions(:transaction_two))
    bank_origin = transfer.merged_sources.find { |origin| origin.src_account_id == @bank.id }

    service = Transaction::Deduplicate.new(sourced, transfer, user: @user, survivor: transfer)
    assert service.call, service.errors.inspect

    assert_empty transfer.reload.transaction_sources
    assert_equal [ simplefin_transactions(:transaction_one), simplefin_transactions(:transaction_two) ],
      bank_origin.reload.transaction_sources.map(&:sourceable).sort_by(&:id)
    assert_includes transfer.badge_transaction_sources.map(&:sourceable), simplefin_transactions(:transaction_two)
  end

  test "corrects only the shared bank account's balance when absorbing into a transfer" do
    transfer = merged_transfer
    # @charge_a, @charge_b and the merged withdrawal each debit @bank by 500.
    assert_equal(-1500, @bank.reload.balance_minor)
    assert_equal 500, @other_bank.reload.balance_minor
    expense_a_before = @expense_a.reload.balance_minor

    Transaction::Deduplicate.new(@charge_a, transfer, user: @user).call

    assert_equal(-1000, @bank.reload.balance_minor)
    assert_equal 500, @other_bank.reload.balance_minor
    assert_equal expense_a_before - 500, @expense_a.reload.balance_minor
  end

  test "unmerging the surviving transfer restores the origin with the absorbed source" do
    transfer = merged_transfer
    sourced = sourced_duplicate(simplefin_transactions(:transaction_two))
    Transaction::Deduplicate.new(sourced, transfer, user: @user).call

    unmerge = Transaction::Unmerge.new(transfer.reload, user: @user)
    assert unmerge.call, unmerge.errors.inspect

    restored = unmerge.restored_transactions.find { |origin| origin.src_account_id == @bank.id }
    assert_equal 500, restored.reload.amount_minor
    assert_includes restored.transaction_sources.map(&:sourceable), simplefin_transactions(:transaction_two)
    # @charge_a + @charge_b + the restored withdrawal; the absorbed duplicate stays gone.
    assert_equal(-1500, @bank.reload.balance_minor)
  end

  test "rejects a one-sided survivor when a transfer is selected" do
    transfer = merged_transfer
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user, survivor: @charge_a)
    assert_not service.call
    assert_includes service.errors, "The transfer must be the transaction to keep"
  end

  test "rejects two transfers" do
    service = Transaction::Deduplicate.new(@charge_a, plain_transfer, plain_transfer, user: @user)
    assert_not service.call
    assert_includes service.errors, "Select at most one transfer to combine into"
  end

  test "rejects a transfer with no one-sided row" do
    service = Transaction::Deduplicate.new(plain_transfer, plain_transfer, user: @user)
    assert_not service.call
  end

  test "rejects a transfer on a different bank account" do
    third_bank = Account.create!(user: @user, name: "Third Bank", kind: :asset, currency: @currency)
    transfer = Transaction.create!(
      user: @user, src_account: third_bank, dest_account: @other_bank,
      amount_minor: 500, currency: @currency, description: "Elsewhere",
      transacted_at: 1.day.ago
    )
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
    assert_not service.call
    assert_includes service.errors, "All transactions must use the same bank account on the same side"
  end

  test "rejects a transfer on the opposite side of the bank account" do
    transfer = Transaction.create!(
      user: @user, src_account: @other_bank, dest_account: @bank,
      amount_minor: 500, currency: @currency, description: "Inbound",
      transacted_at: 1.day.ago
    )
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
    assert_not service.call
  end

  test "rejects an excluded transfer" do
    transfer = plain_transfer
    transfer.update_columns(excluded_at: Time.current)
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
    assert_not service.call
  end

  test "rejects a merge result whose origins do not touch the shared bank account" do
    transfer = merged_transfer
    transfer.merged_sources.each { |origin| origin.update_columns(src_account_id: @other_bank.id) }
    service = Transaction::Deduplicate.new(@charge_a, transfer, user: @user)
    assert_not service.call
    assert Transaction.exists?(@charge_a.id)
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

  test "rejects a one-sided row that is itself a merge result" do
    @charge_b.update_columns(merged_into_id: @charge_a.id)
    service = Transaction::Deduplicate.new(@charge_a, plain_transfer, user: @user)
    assert_not service.call
    assert_includes service.errors, "Merged transactions cannot be combined"
  end

  test "rejects transactions belonging to another user" do
    others = transactions(:opening_balance_revenue)
    service = Transaction::Deduplicate.new(@charge_a, others, user: @user)
    assert_not service.call
  end

  private

    # A hand-made @bank → @other_bank transfer with no merged_sources.
    def plain_transfer
      Transaction.create!(
        user: @user, src_account: @bank, dest_account: @other_bank,
        amount_minor: 500, currency: @currency, description: "Transfer",
        transacted_at: 1.day.ago
      )
    end

    # The shape from issue 258: a sourced @bank → expense withdrawal merged
    # with a revenue → @other_bank deposit, so the result is a transfer whose
    # provenance lives on its zeroed merged_sources.
    def merged_transfer
      revenue = Account.create!(user: @user, name: "Transfer In", kind: :revenue, currency: @currency)
      withdrawal = create_sourced_transaction(
        user: @user, src_account: @bank, dest_account: @expense_b,
        amount_minor: 500, currency: @currency, description: "Posted charge",
        transacted_at: 1.day.ago, sourceable: simplefin_transactions(:transaction_one)
      )
      deposit = Transaction.create!(
        user: @user, src_account: revenue, dest_account: @other_bank,
        amount_minor: 500, currency: @currency, description: "Posted deposit",
        transacted_at: 1.day.ago
      )
      merge = Transaction::Merge.new(withdrawal, deposit, user: @user)
      assert merge.call, merge.errors.inspect
      merge.merged_transaction
    end

    # A one-sided @bank → @expense_a duplicate carrying the given feed row.
    def sourced_duplicate(sourceable)
      create_sourced_transaction(
        user: @user, src_account: @bank, dest_account: @expense_a,
        amount_minor: 500, currency: @currency, description: "Pending charge",
        transacted_at: 2.days.ago, sourceable: sourceable
      )
    end
end
