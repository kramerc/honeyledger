class BackfillAccountAndTransactionSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    duplicate_transaction_sourceables = connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT sourceable_type, sourceable_id
        FROM transactions
        WHERE sourceable_type IS NOT NULL AND sourceable_id IS NOT NULL
        GROUP BY sourceable_type, sourceable_id
        HAVING COUNT(*) > 1
      ) AS duplicates
    SQL

    if duplicate_transaction_sourceables > 0
      raise <<~MSG.strip
        Found #{duplicate_transaction_sourceables} (sourceable_type, sourceable_id) pair(s) shared
        across multiple transactions rows. The new transaction_sources unique index would silently
        drop all but one of those legacy links during backfill. Investigate and clean these up
        before re-running this migration.
      MSG
    end

    execute <<~SQL
      INSERT INTO account_sources (account_id, sourceable_type, sourceable_id, created_at, updated_at)
      SELECT id, sourceable_type, sourceable_id, NOW(), NOW()
      FROM accounts
      WHERE sourceable_type IS NOT NULL AND sourceable_id IS NOT NULL
      ON CONFLICT (sourceable_type, sourceable_id) DO NOTHING
    SQL

    execute <<~SQL
      INSERT INTO transaction_sources (transaction_id, sourceable_type, sourceable_id, created_at, updated_at)
      SELECT id, sourceable_type, sourceable_id, NOW(), NOW()
      FROM transactions
      WHERE sourceable_type IS NOT NULL AND sourceable_id IS NOT NULL
      ON CONFLICT (sourceable_type, sourceable_id) DO NOTHING
    SQL
  end

  def down
    # Intentionally a no-op: this migration is forward-only. Truncating the join
    # tables on rollback would also delete rows that normal application traffic
    # added after the backfill ran. If you need to reverse the M:M cutover, drop
    # the join tables in a separate migration.
  end
end
