class BackfillAccountAndTransactionSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
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
    execute "DELETE FROM account_sources"
    execute "DELETE FROM transaction_sources"
  end
end
