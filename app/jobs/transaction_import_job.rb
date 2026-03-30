class TransactionImportJob < ApplicationJob
  queue_as :default

  def perform(simplefin_account_id: nil, lunchflow_account_id: nil)
    if simplefin_account_id.nil? && lunchflow_account_id.nil?
      import_simplefin_transactions(nil)
      import_lunchflow_transactions(nil)
    else
      import_simplefin_transactions(simplefin_account_id) if simplefin_account_id
      import_lunchflow_transactions(lunchflow_account_id) if lunchflow_account_id
    end
  end

  private

    def import_simplefin_transactions(simplefin_account_id)
      # Find SimpleFIN accounts that are linked to a ledger account
      linked_account_ids = Account.where(sourceable_type: "Simplefin::Account")
        .where.not(sourceable_id: nil)
        .pluck(:sourceable_id)

      return if linked_account_ids.empty?

      transactions = Simplefin::Transaction
        .where(account_id: linked_account_ids)
        .includes(account: { connection: :user })
        .left_joins(:ledger_transaction)
        .where("transactions.id IS NULL OR simplefin_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01')")

      transactions = transactions.where(account_id: simplefin_account_id) if simplefin_account_id

      transactions.find_each do |sft|
        user = sft.account.connection.user
        src_account = sft.account.ledger_account

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

    def import_lunchflow_transactions(lunchflow_account_id)
      linked_account_ids = Account.where(sourceable_type: "Lunchflow::Account")
        .where.not(sourceable_id: nil)
        .pluck(:sourceable_id)

      return if linked_account_ids.empty?

      transactions = Lunchflow::Transaction
        .where(account_id: linked_account_ids)
        .includes(account: { connection: :user })
        .left_joins(:ledger_transaction)
        .where("transactions.id IS NULL OR lunchflow_transactions.synced_at > COALESCE(transactions.synced_at, '1970-01-01')")

      transactions = transactions.where(account_id: lunchflow_account_id) if lunchflow_account_id

      transactions.find_each do |lft|
        user = lft.account.connection.user
        src_account = lft.account.ledger_account
        description = lft.merchant.presence || lft.description

        # Determine if expense or revenue based on amount
        amount_bd = BigDecimal(lft.amount)
        if amount_bd.negative?
          # Money out = expense: bank -> expense
          transaction_src = src_account
          transaction_dest = find_or_create_account(user, description, :expense, src_account.currency)
        else
          # Money in = revenue: revenue -> bank
          transaction_src = find_or_create_account(user, description, :revenue, src_account.currency)
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

    def find_or_create_account(user, description, fallback_kind, currency)
      rule = user.import_rules.for_description(description).first
      return rule.account if rule

      # Fall back to exact name match / create
      account_name = description.strip.gsub(/\s+/, " ").truncate(50)

      user.accounts.find_or_create_by!(name: account_name, kind: fallback_kind) do |account|
        account.currency = currency
      end
    end
end
