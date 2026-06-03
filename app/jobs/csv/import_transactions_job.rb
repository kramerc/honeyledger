class Csv::ImportTransactionsJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Csv::Import.find_by(id: import_id)
    return if import.nil?

    csv_transactions = Csv::Transaction
      .where(import_id: import.id)
      .includes(import: [ :user, { account: :currency } ])
      .left_joins(:ledger_transactions)
      .where("transactions.id IS NULL OR (transactions.merged_into_id IS NULL AND transactions.excluded_at IS NULL AND csv_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01'))")

    Transaction.collecting_sidebar_broadcasts do
      csv_transactions.find_each do |csv_transaction|
        user = csv_transaction.import.user
        ledger_account = csv_transaction.import.account

        # Sign decides direction once per row: a negative amount is a charge
        # (ledger account on src), non-negative is a refund/credit (ledger on
        # dest). Reused for reconciliation, the re-sync swap, and src/dest
        # assignment below.
        ledger_side = csv_transaction.amount_minor.negative? ? :src : :dest

        existing_source = TransactionSource.find_by(sourceable: csv_transaction)

        if existing_source
          ledger_transaction = existing_source.ledger_transaction
          canonical_source = ledger_transaction.transaction_sources.order(:created_at, :id).first

          unless canonical_source.id == existing_source.id
            ledger_transaction.update!(synced_at: Time.current)
            next
          end

          # If the user re-parsed with a different sign (e.g. they toggled
          # invert_amount), the absolute amount is the same but src/dest need
          # to flip so the ledger account balances move in the correct
          # direction. Swap the existing src/dest in place — the counterpart
          # account stays the same; its kind may now read awkwardly relative
          # to the direction, but the balance-sheet side is correct and the
          # user can re-categorize from the transactions UI.
          ledger_account_was_src = ledger_transaction.src_account_id == ledger_account.id
          should_be_src = ledger_side == :src
          if ledger_account_was_src != should_be_src
            ledger_transaction.src_account, ledger_transaction.dest_account =
              ledger_transaction.dest_account, ledger_transaction.src_account
          end

          ledger_transaction.update!(
            amount_minor: csv_transaction.amount_minor.abs,
            transacted_at: csv_transaction.transacted_at,
            cleared_at: csv_transaction.posted_at,
            synced_at: Time.current
          )
          next
        elsif (match = Transaction::Reconcile.call(
          ledger_account: ledger_account,
          amount_minor: csv_transaction.amount_minor.abs,
          currency_id: ledger_account.currency_id,
          transacted_at: csv_transaction.transacted_at,
          description: csv_transaction.description,
          ledger_side: ledger_side,
          incoming_source: csv_transaction
        ))
          begin
            Transaction.transaction do
              TransactionSource::Attach.call(transaction: match, sourceable: csv_transaction)
              match.update!(synced_at: Time.current)
            end
          rescue TransactionSource::Attach::MismatchedTransaction
            # Another import handled this source; skip this iteration.
          end
          next
        elsif (target = find_merged_duplicate_target(csv_transaction, ledger_account))
          # The row was already imported and then consolidated into a transfer,
          # so Transaction::Reconcile excludes its (now zeroed, merged) ledger
          # transaction from the candidate set. Attach this re-imported row to
          # the same merged original instead of creating a duplicate (#184).
          begin
            Transaction.transaction do
              TransactionSource::Attach.call(transaction: target, sourceable: csv_transaction)
              target.update!(synced_at: Time.current)
            end
          rescue TransactionSource::Attach::MismatchedTransaction
            # Another import handled this source; skip this iteration.
          end
          next
        else
          transaction = Transaction.new
        end

        # Csv::Transaction#description is `""` when the user mapped no
        # description column or the row's cells are blank. Account names
        # can't be blank, and ImportRule matching against an empty string
        # has no useful semantics, so fall back to a placeholder. Users can
        # rename the resulting "(no description)" account afterwards.
        description_for_import = csv_transaction.description.presence || "(no description)"

        rule = user.import_rules.for_description(description_for_import).first
        rule_account = rule&.account
        bs_rule_account = rule_account if rule_account&.balance_sheet?

        kind = ledger_side == :src ? :expense : :revenue
        counterpart = if rule_account && !bs_rule_account
          rule_account
        else
          Account.find_or_create_for_import(user: user, description: description_for_import, kind: kind, currency: ledger_account.currency, skip_rules: true)
        end

        if ledger_side == :src
          transaction_src = ledger_account
          transaction_dest = counterpart
        else
          transaction_src = counterpart
          transaction_dest = ledger_account
        end

        transaction.user = user
        transaction.src_account = transaction_src
        transaction.dest_account = transaction_dest
        transaction.description = description_for_import
        transaction.amount_minor = csv_transaction.amount_minor.abs
        transaction.currency = ledger_account.currency
        transaction.transacted_at = csv_transaction.transacted_at
        transaction.cleared_at = csv_transaction.posted_at
        transaction.synced_at = Time.current
        begin
          Transaction.transaction do
            transaction.save!
            TransactionSource::Attach.call(transaction: transaction, sourceable: csv_transaction)
          end
        rescue TransactionSource::Attach::MismatchedTransaction
          next
        end

        if rule&.exclude?
          Transaction::Exclude.new(transaction, user: user).call
        else
          Transaction::AutoMerge.call(transaction, rule_account: bs_rule_account)
        end
      end
    end

    import.update!(state: "imported", imported_at: Time.current, error: nil)
  end

  private

    # Recognize a re-imported statement line whose prior CSV row was already
    # consolidated (merged) into a transfer. Transaction::Reconcile excludes
    # merged transactions and merge results from its candidate set, so an
    # overlapping re-import of an already-merged row would otherwise create a
    # duplicate ledger transaction and double-count the balance (#184). Find a
    # prior Csv::Transaction from a *different* import into the *same* ledger
    # account with identical content (signed amount, same calendar day,
    # case-insensitively equal description) whose ledger transaction reconcile
    # skipped only because it is a zeroed merged original, and return that single
    # transaction so the new row attaches there instead of duplicating.
    def find_merged_duplicate_target(csv_transaction, ledger_account)
      return nil if csv_transaction.description.blank?

      prior_csv_ids = Csv::Transaction
        .joins(:import)
        .where(csv_imports: { account_id: ledger_account.id })
        .where.not(import_id: csv_transaction.import_id)
        .where(amount_minor: csv_transaction.amount_minor)
        .where("LOWER(csv_transactions.description) = LOWER(?)", csv_transaction.description)
        .where(transacted_at: csv_transaction.transacted_at.beginning_of_day..csv_transaction.transacted_at.end_of_day)
        .select(:id)

      ledger_transaction_ids = TransactionSource
        .where(sourceable_type: "Csv::Transaction", sourceable_id: prior_csv_ids)
        .distinct
        .pluck(:transaction_id)

      # 0 or 2+ distinct matches: ambiguous, fall through and create a new
      # transaction rather than guess (mirrors reconcile's conservative nil).
      return nil unless ledger_transaction_ids.size == 1

      target = Transaction.find(ledger_transaction_ids.first)
      # Only act on reconcile's gap: a zeroed *original* (merged_into_id set),
      # which is also the row that survives a later Transaction::Unmerge. A CSV
      # source is never attached to a merge *result* (results are created
      # sourceless and reconcile excludes them). A live/unmerged single match
      # means reconcile deliberately abstained, so defer to it and fall through.
      target.merged_into_id.present? ? target : nil
    end
end
