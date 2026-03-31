class Lunchflow::ImportTransactionsJob < ApplicationJob
  queue_as :default

  def perform(lunchflow_account_id:)
    linked_account_ids = Account.where(sourceable_type: "Lunchflow::Account")
      .where.not(sourceable_id: nil)
      .pluck(:sourceable_id)

    return if linked_account_ids.empty?

    transactions = Lunchflow::Transaction
      .where(account_id: linked_account_ids)
      .where(account_id: lunchflow_account_id)
      .includes(account: { connection: :user })
      .left_joins(:ledger_transaction)
      .where("transactions.id IS NULL OR lunchflow_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01')")

    transactions.find_each do |lft|
      user = lft.account.connection.user
      src_account = lft.account.ledger_account
      description = lft.merchant.presence || lft.description

      amount_bd = BigDecimal(lft.amount)
      if amount_bd.negative?
        transaction_src = src_account
        transaction_dest = Account.find_or_create_for_import(user: user, description: description, kind: :expense, currency: src_account.currency)
      else
        transaction_src = Account.find_or_create_for_import(user: user, description: description, kind: :revenue, currency: src_account.currency)
        transaction_dest = src_account
      end

      transaction = Transaction.find_or_initialize_by(sourceable: lft)
      transaction.user = user
      transaction.src_account = transaction_src
      transaction.dest_account = transaction_dest
      transaction.description = description
      transaction.amount_minor = lft.amount_minor.abs
      transaction.currency = src_account.currency
      transaction.transacted_at = lft.date || Time.current
      transaction.cleared_at = lft.pending ? nil : lft.date
      transaction.synced_at = Time.current
      transaction.save!
    end
  end
end
