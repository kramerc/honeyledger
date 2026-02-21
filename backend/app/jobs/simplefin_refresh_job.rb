class SimplefinRefreshJob < ApplicationJob
  queue_as :default

  def perform(simplefin_connection_id = nil)
    connections = if simplefin_connection_id
      SimplefinConnection.where(id: simplefin_connection_id)
    else
      SimplefinConnection.where("refreshed_at IS NULL OR refreshed_at < ?", 1.day.ago)
    end

    connections.find_each do |simplefin_connection|
      simplefin_client = simplefin_connection.client
      simplefin_accounts = simplefin_client.accounts(start_date: 1.month.ago.to_i)

      if simplefin_accounts["errors"]&.any?
        errors = simplefin_accounts["errors"]
        Rails.logger.error("SimpleFin API error for connection #{simplefin_connection.id}: #{errors.join(', ')}")
        next
      end

      simplefin_accounts["accounts"].each do |sf_account_data|
        sf_account = SimplefinAccount.find_or_initialize_by(
          simplefin_connection: simplefin_connection,
          remote_id: sf_account_data["id"],
        )
        sf_account.org = sf_account_data["org"]
        sf_account.name = sf_account_data["name"]
        sf_account.currency = sf_account_data["currency"]
        sf_account.balance = sf_account_data["balance"]
        sf_account.available_balance = sf_account_data["available-balance"]
        sf_account.balance_date = sf_account_data["balance-date"] ? Time.at(sf_account_data["balance-date"]) : nil
        sf_account.extra = sf_account_data["extra"]
        sf_account.save!

        sf_account_data["transactions"].each do |sf_transaction_data|
          sf_transaction = SimplefinTransaction.find_or_initialize_by(
            simplefin_account: sf_account,
            remote_id: sf_transaction_data["id"]
          )
          sf_transaction.posted = sf_transaction_data["posted"]&.positive? ? Time.at(sf_transaction_data["posted"]) : nil
          sf_transaction.amount = sf_transaction_data["amount"]
          sf_transaction.description = sf_transaction_data["description"]
          sf_transaction.transacted_at = sf_transaction_data["transacted-at"] ? Time.at(sf_transaction_data["transacted-at"]) : nil
          sf_transaction.pending = sf_transaction_data["pending"]
          sf_transaction.extra = sf_transaction_data["extra"]
          sf_transaction.synced_at = Time.current
          sf_transaction.save!
        end
      end

      simplefin_connection.update!(refreshed_at: Time.current)
    end
  end
end
