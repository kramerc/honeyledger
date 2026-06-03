require "test_helper"

class Csv::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_account = accounts(:asset_account)
    @bank_b = accounts(:linked_asset) # counterpart balance-sheet account for transfers
  end

  test "imports an expense (negative amount_minor)" do
    csv_import = create_csv_import
    csv_transaction = csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 2.days.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current,
      raw: { "Date" => "2026-01-15", "Description" => "Coffee Shop", "Amount" => "-4.75" }
    )

    assert_difference "Transaction.count", 1 do
      assert_difference "Account.count", 1 do # auto-created expense counterpart
        Csv::ImportTransactionsJob.perform_now(csv_import.id)
      end
    end

    transaction = csv_transaction.ledger_transactions.first
    assert_equal @bank_account, transaction.src_account
    assert_equal "Coffee Shop", transaction.dest_account.name
    assert_equal "expense", transaction.dest_account.kind
    assert_equal 475, transaction.amount_minor
    assert_equal @currency, transaction.currency

    assert_equal "imported", csv_import.reload.state
    assert_not_nil csv_import.imported_at
  end

  test "imports a revenue (positive amount_minor)" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Salary Payment",
      amount_minor: 250000,
      synced_at: Time.current
    )

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end

    transaction = Transaction.last
    assert_equal @bank_account, transaction.dest_account
    assert_equal "Salary Payment", transaction.src_account.name
    assert_equal "revenue", transaction.src_account.kind
    assert_equal 250000, transaction.amount_minor
  end

  test "does not re-create a ledger transaction when re-running with no synced_at change" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
  end

  test "re-syncs scalars on the canonical ledger transaction when csv_transaction synced_at advances" do
    csv_import = create_csv_import
    csv_transaction = csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: 2.days.ago
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    ledger_transaction = csv_transaction.ledger_transactions.first
    assert_equal 475, ledger_transaction.amount_minor

    # The user re-uploads / re-parses with a corrected amount; the synced_at on
    # the csv_transaction advances past the ledger transaction's synced_at.
    csv_transaction.update!(amount_minor: -500, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(csv_import.id)

    ledger_transaction.reload
    assert_equal 500, ledger_transaction.amount_minor
  end

  test "secondary csv source skips canonical re-sync but still bumps ledger synced_at" do
    csv_import = create_csv_import
    csv_transaction = csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: 2.days.ago
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    ledger_transaction = csv_transaction.ledger_transactions.first

    # Attach a *second* csv source representing the same transaction. The
    # canonical (older) source remains, so the second source must not overwrite
    # canonical scalars when its synced_at advances.
    secondary = csv_import.transactions.create!(
      row_index: 1,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -999,
      synced_at: Time.current
    )
    TransactionSource.create!(ledger_transaction: ledger_transaction, sourceable: secondary)

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    ledger_transaction.reload
    assert_equal 475, ledger_transaction.amount_minor
  end

  test "applies an import rule that routes to a non-balance-sheet account" do
    csv_import = create_csv_import
    rule_account = Account.create!(user: @user, currency: @currency, name: "Groceries", kind: :expense)
    @user.import_rules.create!(match_pattern: "MARKET", match_type: :contains, priority: 0, account: rule_account)

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "FARMERS MARKET",
      amount_minor: -1500,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    transaction = Transaction.last
    assert_equal rule_account, transaction.dest_account
    assert_equal @bank_account, transaction.src_account
  end

  test "excludes a transaction when an exclude rule matches" do
    csv_import = create_csv_import
    @user.import_rules.create!(match_pattern: "INTERNAL", match_type: :contains, priority: 0, exclude: true)

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "INTERNAL TRANSFER",
      amount_minor: -2000,
      synced_at: Time.current
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    transaction = Transaction.last
    assert transaction.excluded?
  end

  test "reconciles to an existing manual ledger transaction with matching description" do
    csv_import = create_csv_import
    counterpart = Account.create!(user: @user, currency: @currency, name: "Coffee Shop", kind: :expense)

    manual_transaction = Transaction.create!(
      user: @user,
      currency: @currency,
      src_account: @bank_account,
      dest_account: counterpart,
      description: "Coffee Shop",
      amount_minor: 475,
      transacted_at: 1.day.ago.beginning_of_day + 12.hours
    )

    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago.beginning_of_day + 12.hours,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current
    )

    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end

    manual_transaction.reload
    assert_includes manual_transaction.transaction_sources.map(&:sourceable_type), "Csv::Transaction"
    assert_not_nil manual_transaction.synced_at
  end

  test "reconciles an equal same-day charge/refund pair without creating duplicates (#159)" do
    csv_import = create_csv_import
    counterpart = Account.create!(user: @user, currency: @currency, name: "Coffee Shop", kind: :expense)
    same_at = 1.day.ago.beginning_of_day + 12.hours

    charge = Transaction.create!(
      user: @user, currency: @currency,
      src_account: @bank_account, dest_account: counterpart,
      description: "Coffee Shop", amount_minor: 475, transacted_at: same_at
    )
    refund = Transaction.create!(
      user: @user, currency: @currency,
      src_account: counterpart, dest_account: @bank_account,
      description: "Coffee Shop", amount_minor: 475, transacted_at: same_at
    )

    # An overlapping re-import carries the same pair: a charge (negative) and a
    # refund (positive). Each row must reconcile to the matching-direction
    # orphan rather than ambiguously matching both and creating duplicates.
    csv_import.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -475, synced_at: Time.current)
    csv_import.transactions.create!(row_index: 1, transacted_at: same_at, description: "Coffee Shop", amount_minor: 475, synced_at: Time.current)

    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end

    assert_includes charge.reload.transaction_sources.map(&:sourceable_type), "Csv::Transaction"
    assert_includes refund.reload.transaction_sources.map(&:sourceable_type), "Csv::Transaction"
    assert_not_equal charge.transaction_sources.first.sourceable_id,
      refund.transaction_sources.first.sourceable_id,
      "charge and refund must reconcile to distinct CSV rows"
  end

  test "no-ops when the import has no rows" do
    csv_import = create_csv_import
    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
    assert_equal "imported", csv_import.reload.state
  end

  test "no-ops when the import does not exist" do
    assert_nothing_raised do
      Csv::ImportTransactionsJob.perform_now(0)
    end
  end

  test "imports a row whose description is blank without crashing" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "",
      amount_minor: -475,
      synced_at: Time.current
    )

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
    transaction = Transaction.last
    assert_equal "(no description)", transaction.description
    assert_equal "(no description)", transaction.dest_account.name
    assert_equal "imported", csv_import.reload.state
  end

  test "imports two distinct rows from the same CSV that share amount/day/description" do
    csv_import = create_csv_import
    same_at = 1.day.ago.beginning_of_day + 12.hours
    csv_import.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee", amount_minor: -475, synced_at: Time.current)
    csv_import.transactions.create!(row_index: 1, transacted_at: same_at, description: "Coffee", amount_minor: -475, synced_at: Time.current)

    assert_difference "Transaction.count", 2 do
      Csv::ImportTransactionsJob.perform_now(csv_import.id)
    end
  end

  test "swaps src/dest on re-import when the sign flips (e.g. user toggled invert_amount)" do
    csv_import = create_csv_import
    csv_transaction = csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: 2.days.ago
    )

    Csv::ImportTransactionsJob.perform_now(csv_import.id)
    ledger_transaction = csv_transaction.ledger_transactions.first
    assert_equal @bank_account, ledger_transaction.src_account, "ledger_account starts as src for negative amount"

    # User toggles invert_amount; sign flips, synced_at advances.
    csv_transaction.update!(amount_minor: 475, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(csv_import.id)

    ledger_transaction.reload
    assert_equal @bank_account, ledger_transaction.dest_account, "ledger_account moves to dest after sign flip"
    assert_equal 475, ledger_transaction.amount_minor
  end

  test "skips a row cleanly when TransactionSource::Attach raises MismatchedTransaction during create" do
    csv_import = create_csv_import
    csv_import.transactions.create!(
      row_index: 0,
      transacted_at: 1.day.ago,
      description: "Coffee Shop",
      amount_minor: -475,
      synced_at: Time.current
    )

    raise_mismatch = ->(*) { raise TransactionSource::Attach::MismatchedTransaction, "concurrent attach" }
    TransactionSource::Attach.stub(:call, raise_mismatch) do
      assert_no_difference "Transaction.count" do
        Csv::ImportTransactionsJob.perform_now(csv_import.id)
      end
    end
  end

  # --- #184: re-importing an overlapping row whose ledger transaction was merged ---

  test "re-importing a row whose ledger transaction was merged attaches instead of duplicating (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    charge = import_then_merge_charge(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)
    assert_equal 0, charge.amount_minor, "merge zeroes the original"
    assert charge.merged_into_id.present?, "merge sets merged_into_id"

    balance_before = @bank_account.reload.balance_minor

    import_b = create_csv_import
    csv_b = import_b.transactions.create!(
      row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current
    )

    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end

    assert_equal charge, csv_b.reload.ledger_transactions.first, "the re-imported row attaches to the merged original"
    assert_equal balance_before, @bank_account.reload.balance_minor, "the account balance does not double-count"
  end

  test "a genuinely new row in the same re-import is still created (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    import_then_merge_charge(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)

    import_b = create_csv_import
    import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    import_b.transactions.create!(row_index: 1, transacted_at: same_at, description: "Grocery Store", amount_minor: -3000, synced_at: Time.current)

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
    assert_equal "Grocery Store", Transaction.order(:id).last.description
  end

  test "an ambiguous match against multiple merged transactions falls through to a new transaction (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    build_merged_csv_charge_directly(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)
    build_merged_csv_charge_directly(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)

    import_b = create_csv_import
    import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
  end

  test "a single unmerged match is left to Reconcile and not adopted by the merge fallback (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours

    # A prior CSV-sourced, still-unmerged charge.
    import_a = create_csv_import
    import_a.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(import_a.id)

    # A second identical-content unmerged charge with no CSV source, so Reconcile
    # sees two candidates and abstains (size == 2 -> nil), reaching the fallback.
    Transaction.create!(
      user: @user, currency: @currency, src_account: @bank_account, dest_account: accounts(:expense_account),
      amount_minor: 5000, description: "Coffee Shop", transacted_at: same_at
    )

    import_b = create_csv_import
    import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)

    # The single match is unmerged, so the fallback returns nil and a new transaction is created.
    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
  end

  test "a blank-description re-import is not deduped by the merge fallback (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    import_then_merge_charge(description: "", amount_minor: -5000, transacted_at: same_at)

    import_b = create_csv_import
    import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "", amount_minor: -5000, synced_at: Time.current)

    assert_difference "Transaction.count", 1 do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
    assert_equal "(no description)", Transaction.order(:id).last.description
  end

  test "re-running the re-import job after a merge-fallback attach is idempotent (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    import_then_merge_charge(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)

    import_b = create_csv_import
    import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(import_b.id)

    assert_no_difference [ "Transaction.count", "TransactionSource.count" ] do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
  end

  test "an overlapping re-import of an unmerged transaction is still reconciled, not duplicated (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    import_a = create_csv_import
    csv_a = import_a.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(import_a.id)
    charge = csv_a.reload.ledger_transactions.first

    import_b = create_csv_import
    csv_b = import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)

    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(import_b.id)
    end
    assert_equal charge, csv_b.reload.ledger_transactions.first, "Reconcile adopts the unmerged original"
  end

  test "the merge-fallback attachment survives an unmerge of the transfer (#184)" do
    same_at = 1.day.ago.beginning_of_day + 12.hours
    charge = import_then_merge_charge(description: "Coffee Shop", amount_minor: -5000, transacted_at: same_at)
    transfer = Transaction.find(charge.merged_into_id)

    import_b = create_csv_import
    csv_b = import_b.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    Csv::ImportTransactionsJob.perform_now(import_b.id)
    assert_equal charge, csv_b.reload.ledger_transactions.first

    assert Transaction::Unmerge.new(transfer, user: @user).call
    charge.reload
    assert_nil charge.merged_into_id, "unmerge restores the original"
    assert_equal 5000, charge.amount_minor
    assert_equal 2, charge.transaction_sources.where(sourceable_type: "Csv::Transaction").count,
      "both CSV sources survive on the restored original"

    # A later overlapping re-import now reconciles to the restored original.
    import_c = create_csv_import
    import_c.transactions.create!(row_index: 0, transacted_at: same_at, description: "Coffee Shop", amount_minor: -5000, synced_at: Time.current)
    assert_no_difference "Transaction.count" do
      Csv::ImportTransactionsJob.perform_now(import_c.id)
    end
  end

  private

    # Import a charge through the job, then consolidate it into a BS->BS transfer
    # via Transaction::Merge. Returns the now-zeroed, merged original.
    def import_then_merge_charge(description:, amount_minor:, transacted_at:)
      import = create_csv_import
      csv_row = import.transactions.create!(
        row_index: 0, transacted_at: transacted_at, description: description,
        amount_minor: amount_minor, synced_at: Time.current
      )
      Csv::ImportTransactionsJob.perform_now(import.id)
      charge = csv_row.reload.ledger_transactions.first

      revenue = Account.create!(user: @user, currency: @currency, name: "Transfer In #{import.id}", kind: :revenue)
      counterpart = Transaction.create!(
        user: @user, currency: @currency, src_account: revenue, dest_account: @bank_b,
        amount_minor: amount_minor.abs, description: description.presence || "Transfer", transacted_at: transacted_at
      )
      assert Transaction::Merge.new(charge, counterpart, user: @user).call
      charge.reload
    end

    # Build a CSV-sourced charge that is already merged, WITHOUT going through the
    # import job's dedup, so multiple identical-content merged transactions can
    # coexist (for the ambiguity test).
    def build_merged_csv_charge_directly(description:, amount_minor:, transacted_at:)
      import = create_csv_import
      csv_row = import.transactions.create!(
        row_index: 0, transacted_at: transacted_at, description: description,
        amount_minor: amount_minor, synced_at: Time.current
      )
      expense = Account.create!(user: @user, currency: @currency, name: "Expense #{import.id}", kind: :expense)
      charge = Transaction.create!(
        user: @user, currency: @currency, src_account: @bank_account, dest_account: expense,
        amount_minor: amount_minor.abs, description: description, transacted_at: transacted_at
      )
      TransactionSource.create!(ledger_transaction: charge, sourceable: csv_row)

      revenue = Account.create!(user: @user, currency: @currency, name: "Revenue #{import.id}", kind: :revenue)
      counterpart = Transaction.create!(
        user: @user, currency: @currency, src_account: revenue, dest_account: @bank_b,
        amount_minor: amount_minor.abs, description: description, transacted_at: transacted_at
      )
      assert Transaction::Merge.new(charge, counterpart, user: @user).call
      charge.reload
    end

    def create_csv_import
      csv_import = Csv::Import.new(user: @user, account: @bank_account, state: "parsed")
      csv_import.file.attach(
        io: StringIO.new("Date,Description,Amount\n"),
        filename: "stub.csv",
        content_type: "text/csv"
      )
      csv_import.save!
      csv_import
    end
end
