class Simplefin::TransactionImportJob < ApplicationJob
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
      .where("transactions.id IS NULL OR simplefin_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01')")

    transactions.find_each do |sft|
      user = sft.account.connection.user
      src_account = sft.account.ledger_account

      amount_bd = BigDecimal(sft.amount)
      if amount_bd.negative?
        transaction_src = src_account
        transaction_dest = Account.find_or_create_for_import(user: user, description: sft.description, kind: :expense, currency: src_account.currency)
      else
        transaction_src = Account.find_or_create_for_import(user: user, description: sft.description, kind: :revenue, currency: src_account.currency)
        transaction_dest = src_account
      end

      transaction = Transaction.find_or_initialize_by(sourceable: sft)
      transaction.user = user
      transaction.src_account = transaction_src
      transaction.dest_account = transaction_dest
      transaction.description = sft.description
      transaction.amount_minor = sft.amount_minor.abs
      transaction.currency = src_account.currency
      transaction.transacted_at = sft.transacted_at || sft.posted || Time.current
      transaction.cleared_at = sft.posted
      transaction.synced_at = Time.current
      transaction.save!
    end
  end
end
