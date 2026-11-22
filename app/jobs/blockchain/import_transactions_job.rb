class Blockchain::ImportTransactionsJob < ApplicationJob
  queue_as :default

  FEE_ACCOUNT_NAME = "Network fees".freeze

  def perform(blockchain_account_id:)
    return unless AccountSource.exists?(sourceable_type: "Blockchain::Account", sourceable_id: blockchain_account_id)

    transactions = Blockchain::Transaction
      .confirmed
      .where(account_id: blockchain_account_id)
      .includes(account: { connection: :user })
      .left_joins(:ledger_transactions)
      .where("transactions.id IS NULL OR (transactions.merged_into_id IS NULL AND transactions.excluded_at IS NULL AND blockchain_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01'))")

    Transaction.collecting_sidebar_broadcasts do
      transactions.find_each do |blockchain_transaction|
        user = blockchain_transaction.account.connection.user
        ledger_account = blockchain_transaction.account.ledger_accounts.first
        next if ledger_account.nil?

        description = blockchain_transaction.resolved_description
        transacted_at = blockchain_transaction.transacted_at || Time.current

        # On-chain amounts are signed correctly, so InferLedgerSide's transfer
        # override never fires here; the descriptions avoid its wording too.
        direction = blockchain_transaction.ledger_direction
        ledger_side = direction.ledger_side

        existing_source = TransactionSource.find_by(sourceable: blockchain_transaction)

        if existing_source
          ledger_transaction = existing_source.ledger_transaction
          canonical_source = ledger_transaction.transaction_sources.order(:created_at, :id).first

          # A secondary source never overwrites canonical fields (first writer wins).
          unless canonical_source.id == existing_source.id
            ledger_transaction.mark_synced_by_secondary_source!(canonical_source, blockchain_transaction)
            next
          end

          ledger_transaction.update!(
            amount_minor: blockchain_transaction.amount_minor.abs,
            transacted_at: transacted_at,
            cleared_at: transacted_at,
            synced_at: blockchain_transaction.synced_at || Time.current
          )
          next
        elsif (match = Transaction::Reconcile.call(
          ledger_account: ledger_account,
          amount_minor: blockchain_transaction.amount_minor.abs,
          currency_id: ledger_account.currency_id,
          transacted_at: transacted_at,
          description: description,
          ledger_side: ledger_side,
          incoming_source: blockchain_transaction
        ))
          begin
            Transaction.transaction do
              canonical_source = match.transaction_sources.order(:created_at, :id).first
              TransactionSource::Attach.call(
                transaction: match, sourceable: blockchain_transaction,
                direction_overridden: direction.direction_overridden?
              )
              match.mark_synced_by_secondary_source!(canonical_source, blockchain_transaction)
            end
          rescue TransactionSource::Attach::MismatchedTransaction
            # Another import handled this source; skip this iteration.
          end
          next
        else
          transaction = Transaction.new
        end

        rule = user.import_rules.for_description(description).first unless blockchain_transaction.fee?
        rule_account = rule&.account
        bs_rule_account = rule_account if rule_account&.balance_sheet?

        kind = ledger_side == :src ? :expense : :revenue
        counterpart = if rule_account && !bs_rule_account
          rule_account
        else
          # One shared counterpart per direction rather than one account per
          # counterparty address; the address stays in the description, where
          # an import rule can pick it up.
          Account.find_or_create_for_import(
            user: user, description: counterpart_name(blockchain_transaction, kind),
            kind: kind, currency: ledger_account.currency, skip_rules: true
          )
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
        transaction.description = description
        transaction.amount_minor = blockchain_transaction.amount_minor.abs
        transaction.currency = ledger_account.currency
        transaction.transacted_at = transacted_at
        transaction.cleared_at = transacted_at
        transaction.synced_at = blockchain_transaction.synced_at || Time.current
        begin
          Transaction.transaction do
            transaction.save!
            TransactionSource::Attach.call(
              transaction: transaction, sourceable: blockchain_transaction,
              direction_overridden: direction.direction_overridden?
            )
          end
        rescue TransactionSource::Attach::MismatchedTransaction
          next
        end

        if rule&.exclude?
          Transaction::Exclude.new(transaction, user: user).call
        elsif !blockchain_transaction.fee?
          # A fee is never one leg of a transfer, so it is not offered to AutoMerge.
          Transaction::AutoMerge.call(transaction, rule_account: bs_rule_account)
        end
      end
    end
  end

  private

    def counterpart_name(blockchain_transaction, kind)
      return FEE_ACCOUNT_NAME if blockchain_transaction.fee?

      asset_name = blockchain_transaction.account.name.presence || "Crypto"
      kind == :expense ? "#{asset_name} sent" : "#{asset_name} received"
    end
end
