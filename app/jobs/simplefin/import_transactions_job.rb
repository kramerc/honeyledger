class Simplefin::ImportTransactionsJob < ApplicationJob
  queue_as :default

  def perform(simplefin_account_id:)
    return unless AccountSource.exists?(sourceable_type: "Simplefin::Account", sourceable_id: simplefin_account_id)

    transactions = Simplefin::Transaction
      .where(account_id: simplefin_account_id)
      .includes(account: { connection: :user })
      .left_joins(:ledger_transactions)
      .where("transactions.id IS NULL OR (transactions.merged_into_id IS NULL AND transactions.excluded_at IS NULL AND simplefin_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01'))")

    Transaction.collecting_sidebar_broadcasts do
      transactions.find_each do |sft|
        user = sft.account.connection.user
        ledger_account = sft.account.ledger_accounts.first
        next if ledger_account.nil?

        # Sign decides direction once per row: a negative amount is a charge
        # (ledger account on src), non-negative is a refund/credit (ledger on
        # dest). Reused below for both reconciliation and src/dest assignment.
        amount_bd = BigDecimal(sft.amount)
        ledger_side = amount_bd.negative? ? :src : :dest

        existing_source = TransactionSource.find_by(sourceable: sft)

        if existing_source
          ledger_transaction = existing_source.ledger_transaction
          canonical_source = ledger_transaction.transaction_sources.order(:created_at, :id).first

          # Re-sync only when this source is the first writer of the ledger transaction.
          # Secondary sources never overwrite canonical fields, but we still bump the
          # ledger transaction's synced_at so the outer query's
          # `sft.synced_at > ledger.synced_at` filter stops re-matching this row
          # until the canonical source's data actually advances again.
          unless canonical_source.id == existing_source.id
            ledger_transaction.update!(synced_at: Time.current)
            next
          end

          # Refresh source-driven scalars only. Counterpart account, description,
          # and merge/exclude state were settled at first import (possibly adjusted
          # by AutoMerge or by the user) and must not be re-derived on every resync —
          # re-running counterpart creation here is what produced #137.
          ledger_transaction.update!(
            amount_minor: sft.amount_minor.abs,
            transacted_at: sft.transacted_at || sft.posted || Time.current,
            cleared_at: sft.posted,
            synced_at: Time.current
          )
          next
        elsif (match = Transaction::Reconcile.call(
          ledger_account: ledger_account,
          amount_minor: sft.amount_minor.abs,
          currency_id: ledger_account.currency_id,
          transacted_at: sft.transacted_at || sft.posted || Time.current,
          description: sft.description,
          ledger_side: ledger_side,
          incoming_source: sft
        ))
          # Same concurrent-attach guard as the new-creation branch below — if a
          # parallel job attaches this source between Reconcile returning and our
          # insert, the AR transaction rolls back and we move on.
          begin
            Transaction.transaction do
              TransactionSource::Attach.call(transaction: match, sourceable: sft)
              match.update!(synced_at: Time.current)
            end
          rescue TransactionSource::Attach::MismatchedTransaction
            # Another import handled this source; skip this iteration.
          end
          next
        else
          transaction = Transaction.new
        end

        rule = user.import_rules.for_description(sft.description).first
        rule_account = rule&.account
        bs_rule_account = rule_account if rule_account&.balance_sheet?

        kind = amount_bd.negative? ? :expense : :revenue
        counterpart = if rule_account && !bs_rule_account
          rule_account
        else
          Account.find_or_create_for_import(user: user, description: sft.description, kind: kind, currency: ledger_account.currency, skip_rules: true)
        end

        if amount_bd.negative?
          transaction_src = ledger_account
          transaction_dest = counterpart
        else
          transaction_src = counterpart
          transaction_dest = ledger_account
        end

        transaction.user = user
        transaction.src_account = transaction_src
        transaction.dest_account = transaction_dest
        transaction.description = sft.description
        transaction.amount_minor = sft.amount_minor.abs
        transaction.currency = ledger_account.currency
        transaction.transacted_at = sft.transacted_at || sft.posted || Time.current
        transaction.cleared_at = sft.posted
        transaction.synced_at = Time.current
        # Wrap save+attach so a concurrent import that creates the source row
        # first rolls back this iteration cleanly instead of leaving an
        # orphaned ledger transaction with no source.
        begin
          Transaction.transaction do
            transaction.save!
            TransactionSource::Attach.call(transaction: transaction, sourceable: sft)
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
  end
end
