require "test_helper"

class Csv::ImportTransactionsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_account = accounts(:asset_account)
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

  private

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
