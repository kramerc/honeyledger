class AddLastSeenAtToSimplefinAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :simplefin_accounts, :last_seen_at, :datetime

    execute <<~SQL.squish
      UPDATE simplefin_accounts
      SET last_seen_at = simplefin_connections.refreshed_at
      FROM simplefin_connections
      WHERE simplefin_accounts.connection_id = simplefin_connections.id
        AND simplefin_connections.refreshed_at IS NOT NULL
    SQL
  end

  def down
    remove_column :simplefin_accounts, :last_seen_at
  end
end
