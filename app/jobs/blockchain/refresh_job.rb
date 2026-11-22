class Blockchain::RefreshJob < ApplicationJob
  queue_as :default

  # The asset each chain's native account tracks, keyed by chain.
  NATIVE_ASSETS = {
    "bitcoin" => { remote_id: "BTC", name: "Bitcoin", currency: "BTC" }
  }.freeze

  def perform(blockchain_connection_id = nil)
    connections = if blockchain_connection_id
      Blockchain::Connection.where(id: blockchain_connection_id)
    else
      Blockchain::Connection.where("refreshed_at IS NULL OR refreshed_at < ?", 1.day.ago)
    end

    connections.find_each do |blockchain_connection|
      refreshed_at = Time.current
      refresh_connection(blockchain_connection, refreshed_at)
    rescue EsploraClient::Error => e
      blockchain_connection.update!(error: e.message, refreshed_at: refreshed_at)
    end
  end

  private

    def refresh_connection(blockchain_connection, refreshed_at)
      result = Blockchain::Bitcoin::Scanner.call(blockchain_connection)
      asset = NATIVE_ASSETS.fetch(blockchain_connection.chain)

      blockchain_account = blockchain_connection.accounts.find_or_initialize_by(remote_id: asset[:remote_id])
      blockchain_account.name = asset[:name]
      blockchain_account.currency = asset[:currency]
      blockchain_account.last_seen_at = refreshed_at
      blockchain_account.balance = result.balance
      # The chain gives no "balance as of" beyond the tip, so record when it last moved.
      blockchain_account.balance_changed_at = refreshed_at if blockchain_account.balance_changed? || blockchain_account.balance_changed_at.nil?
      blockchain_account.save!

      result.rows.each do |row|
        blockchain_transaction = blockchain_account.transactions.find_or_initialize_by(remote_id: row.remote_id)
        blockchain_transaction.txid = row.txid
        blockchain_transaction.kind = row.kind
        blockchain_transaction.amount = row.amount
        blockchain_transaction.counterparty = row.counterparty
        blockchain_transaction.block_height = row.block_height
        blockchain_transaction.transacted_at = row.transacted_at
        blockchain_transaction.confirmed = row.confirmed
        # Advance synced_at only when the row is new or changed, so the import
        # job does not rewrite every imported transaction on every refresh.
        blockchain_transaction.synced_at = Time.current if blockchain_transaction.changed?
        blockchain_transaction.save!
      end

      blockchain_connection.update!(error: nil, refreshed_at: refreshed_at)

      Blockchain::ImportTransactionsJob.perform_later(blockchain_account_id: blockchain_account.id) if blockchain_account.linked?
    end
end
