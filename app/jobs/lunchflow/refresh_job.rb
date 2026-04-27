class Lunchflow::RefreshJob < ApplicationJob
  queue_as :default

  def perform(lunchflow_connection_id = nil)
    connections = if lunchflow_connection_id
      Lunchflow::Connection.where(id: lunchflow_connection_id)
    else
      Lunchflow::Connection.where("refreshed_at IS NULL OR refreshed_at < ?", 1.day.ago)
    end

    connections.find_each do |lunchflow_connection|
      refreshed_at = Time.current
      refresh_connection(lunchflow_connection, refreshed_at)
    rescue LunchflowClient::Error => e
      lunchflow_connection.update!(error: e.message, refreshed_at: refreshed_at)
    end
  end

  private

    def refresh_connection(lunchflow_connection, refreshed_at)
      client = lunchflow_connection.client
      api_accounts = client.accounts

      api_accounts.each do |api_account|
        refresh_account(client, lunchflow_connection, api_account, refreshed_at)
      rescue LunchflowClient::Error => e
        Rails.logger.error("Lunchflow refresh failed for account #{api_account["id"]}: #{e.message}")
      end

      lunchflow_connection.update!(error: nil, refreshed_at: refreshed_at)
    end

    def refresh_account(client, lunchflow_connection, api_account, refreshed_at)
      lf_account = Lunchflow::Account.find_or_initialize_by(
        connection: lunchflow_connection,
        remote_id: api_account["id"]
      )
      lf_account.name = api_account["name"]
      lf_account.institution_name = api_account["institution_name"]
      lf_account.institution_logo = api_account["institution_logo"]
      lf_account.provider = api_account["provider"]
      lf_account.currency = api_account["currency"]
      lf_account.status = api_account["status"]

      balance_data = client.balance(api_account["id"])
      lf_account.balance = balance_data["amount"].to_s
      lf_account.currency ||= balance_data["currency"]

      lf_account.last_seen_at = refreshed_at
      lf_account.save!

      api_transactions = client.transactions(api_account["id"], include_pending: true)
      api_transactions.each do |api_txn|
        # Skip pending transactions with no ID (can't upsert without identifier)
        next if api_txn["id"].nil?

        lf_transaction = Lunchflow::Transaction.find_or_initialize_by(
          account: lf_account,
          remote_id: api_txn["id"]
        )
        lf_transaction.amount = api_txn["amount"].to_s
        lf_transaction.currency = api_txn["currency"]
        lf_transaction.description = api_txn["description"]
        lf_transaction.merchant = api_txn["merchant"]
        lf_transaction.pending = api_txn["isPending"]
        lf_transaction.date = api_txn["date"]
        lf_transaction.synced_at = Time.current
        lf_transaction.save!
      end

      Lunchflow::ImportTransactionsJob.perform_later(lunchflow_account_id: lf_account.id) if lf_account.linked?
    end
end
