class Simplefin::ImportTransactionsJob < ApplicationJob
  queue_as :default

  def perform(simplefin_account_id:)
    linked_account_ids = Account.where(sourceable_type: "Simplefin::Account")
      .where.not(sourceable_id: nil)
      .pluck(:sourceable_id)

    return if linked_account_ids.empty?

    transactions = Simplefin::Transaction
      .where(account_id: linked_account_ids)
      .where(account_id: simplefin_account_id)
      .includes(account: { connection: :user })
      .left_joins(:ledger_transaction)
      .where("transactions.id IS NULL OR (transactions.merged_into_id IS NULL AND transactions.excluded_at IS NULL AND simplefin_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01'))")

    Transaction.collecting_sidebar_broadcasts do
      transactions.find_each do |sft|
        user = sft.account.connection.user
        ledger_account = sft.account.ledger_account

        amount_bd = BigDecimal(sft.amount)
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

        transaction = Transaction.find_or_initialize_by(sourceable: sft)
        transaction.user = user
        transaction.src_account = transaction_src
        transaction.dest_account = transaction_dest
        transaction.description = sft.description
        transaction.amount_minor = sft.amount_minor.abs
        transaction.currency = ledger_account.currency
        transaction.transacted_at = sft.transacted_at || sft.posted || Time.current
        transaction.cleared_at = sft.posted
        transaction.synced_at = Time.current
        transaction.save!

        if rule&.exclude?
          Transaction::Exclude.new(transaction, user: user).call
        else
          Transaction::AutoMerge.call(transaction, rule_account: bs_rule_account)
        end
      end
    end
  end
end
