class AddLastSeenAtToLunchflowAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :lunchflow_accounts, :last_seen_at, :datetime

    execute <<~SQL.squish
      UPDATE lunchflow_accounts
      SET last_seen_at = lunchflow_connections.refreshed_at
      FROM lunchflow_connections
      WHERE lunchflow_accounts.connection_id = lunchflow_connections.id
        AND lunchflow_connections.refreshed_at IS NOT NULL
    SQL
  end

  def down
    remove_column :lunchflow_accounts, :last_seen_at
  end
end
