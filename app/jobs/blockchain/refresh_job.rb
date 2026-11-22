class Blockchain::RefreshJob < ApplicationJob
  queue_as :default

  # One refresh per wallet at a time: a paced xpub scan takes minutes, and two
  # overlapping scans would race on the derived-address cache and double the
  # request rate against the explorer.
  limits_concurrency to: 1, key: ->(blockchain_connection_id = nil) { "blockchain-refresh-#{blockchain_connection_id || "sweep"}" }, duration: 30.minutes

  # The asset each chain's native account tracks, keyed by chain.
  NATIVE_ASSETS = {
    "bitcoin" => { remote_id: "BTC", name: "Bitcoin", currency: "BTC" },
    "ethereum" => { remote_id: "ETH", name: "Ethereum", currency: "ETH" }
  }.freeze

  # The service that turns each chain's explorer data into Blockchain::Scan rows.
  SCANNERS = {
    "bitcoin" => Blockchain::Bitcoin::Scanner,
    "ethereum" => Blockchain::Ethereum::Scanner
  }.freeze

  CLIENT_ERRORS = [ EsploraClient::Error, EvmExplorerClient::Error ].freeze

  NO_ACTIVITY_MESSAGE = "No activity found for this key. An xpub is read as a legacy (1…) wallet; " \
    "for a native SegWit (bc1q…) wallet add its zpub, and for nested SegWit (3…) its ypub.".freeze

  # With an id, refreshes that wallet. Without one, enqueues a refresh per
  # stale wallet, so every scan runs under its own wallet's concurrency key and
  # a sweep cannot overlap a manual refresh of the same wallet.
  def perform(blockchain_connection_id = nil)
    if blockchain_connection_id.nil?
      Blockchain::Connection.where("refreshed_at IS NULL OR refreshed_at < ?", 1.day.ago).find_each(&:refresh)
      return
    end

    blockchain_connection = Blockchain::Connection.find_by(id: blockchain_connection_id)
    return if blockchain_connection.nil?

    refreshed_at = Time.current
    begin
      refresh_connection(blockchain_connection, refreshed_at)
    rescue *CLIENT_ERRORS => e
      blockchain_connection.update!(error: e.message, refreshed_at: refreshed_at)
    end
  end

  private

    def refresh_connection(blockchain_connection, refreshed_at)
      result = SCANNERS.fetch(blockchain_connection.chain).call(blockchain_connection)
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

      prune_vanished_rows(blockchain_account, result.rows.map(&:remote_id))

      error = NO_ACTIVITY_MESSAGE if blockchain_connection.extended_key? && result.used_addresses.zero?
      # A scan that succeeded can still have something to say (a balance its
      # history does not explain); it shows where refresh errors do, and the
      # next refresh clears it once resolved.
      error ||= result.warning
      blockchain_connection.update!(error: error, refreshed_at: refreshed_at)

      Blockchain::ImportTransactionsJob.perform_later(blockchain_account_id: blockchain_account.id) if blockchain_account.linked?
    end

    # A row the scanner no longer reports (a reorg, or a movement that now nets
    # to zero) is deleted while it has not reached the ledger. One already
    # imported is kept and logged: removing a ledger transaction, which the user
    # may have edited or merged, is not something a refresh should do silently.
    def prune_vanished_rows(blockchain_account, current_remote_ids)
      vanished = blockchain_account.transactions.where.not(remote_id: current_remote_ids)
      imported, unimported = vanished.includes(:transaction_sources).partition { |row| row.transaction_sources.any? }

      unimported.each(&:destroy!)
      imported.each do |row|
        Rails.logger.warn("Blockchain row #{row.remote_id} on account #{blockchain_account.id} no longer appears on chain but is imported; left in place")
      end
    end
end
