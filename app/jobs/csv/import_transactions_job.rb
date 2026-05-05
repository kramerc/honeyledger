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
          should_be_src = csv_transaction.amount_minor.negative?
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
        else
          transaction = Transaction.new
        end

        rule = user.import_rules.for_description(csv_transaction.description).first
        rule_account = rule&.account
        bs_rule_account = rule_account if rule_account&.balance_sheet?

        kind = csv_transaction.amount_minor.negative? ? :expense : :revenue
        counterpart = if rule_account && !bs_rule_account
          rule_account
        else
          Account.find_or_create_for_import(user: user, description: csv_transaction.description, kind: kind, currency: ledger_account.currency, skip_rules: true)
        end

        if csv_transaction.amount_minor.negative?
          transaction_src = ledger_account
          transaction_dest = counterpart
        else
          transaction_src = counterpart
          transaction_dest = ledger_account
        end

        transaction.user = user
        transaction.src_account = transaction_src
        transaction.dest_account = transaction_dest
        transaction.description = csv_transaction.description
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
end
