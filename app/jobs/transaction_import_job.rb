class TransactionImportJob < ApplicationJob
  queue_as :default

  def perform(simplefin_account_id: nil)
    scope = SimplefinTransaction
      .includes(simplefin_account: { simplefin_connection: :user, account: :currency }).where.not(simplefin_account: { account_id: nil })
      .left_joins(:ledger_transaction)
      .where("transactions.id IS NULL OR simplefin_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01')")

    scope = scope.where(simplefin_account_id: simplefin_account_id) if simplefin_account_id

    scope.find_each do |sft|
        user = sft.simplefin_account.simplefin_connection.user
        src_account = sft.simplefin_account.account

        # Determine if expense or revenue based on amount
        amount_bd = BigDecimal(sft.amount)
        if amount_bd.negative?
          # Money out = expense: bank -> expense
          transaction_src = src_account
          transaction_dest = find_or_create_account(user, sft.description, :expense, src_account.currency)
        else
          # Money in = revenue: revenue -> bank
          transaction_src = find_or_create_account(user, sft.description, :revenue, src_account.currency)
          transaction_dest = src_account
        end

        transaction = Transaction.find_or_initialize_by(
          sourceable: sft
        )
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

  private

  def find_or_create_account(user, description, kind, currency)
    # Sanitize description for account name
    account_name = description.strip.gsub(/\s+/, " ").truncate(50)

    user.accounts.find_or_create_by!(name: account_name, kind: kind) do |account|
      account.currency = currency
    end
  end
end
