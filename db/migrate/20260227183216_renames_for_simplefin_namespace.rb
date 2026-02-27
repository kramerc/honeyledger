class RenamesForSimplefinNamespace < ActiveRecord::Migration[8.1]
  def change
    rename_column :simplefin_accounts, :simplefin_connection_id, :connection_id
    rename_column :simplefin_accounts, :account_id, :ledger_account_id
    rename_column :simplefin_transactions, :simplefin_account_id, :account_id
  end
end
