class UpgradeSimplefinToV2 < ActiveRecord::Migration[8.1]
  def change
    add_column :simplefin_accounts, :conn_id, :string
    remove_column :simplefin_connections, :account_errors, :string, default: [], null: false, array: true
    add_column :simplefin_connections, :errlist, :jsonb, default: [], null: false
  end
end
