class DropLegacySourceableColumns < ActiveRecord::Migration[8.1]
  def change
    remove_index :accounts, name: "index_accounts_on_sourceable", column: [ :sourceable_type, :sourceable_id ], unique: true
    remove_column :accounts, :sourceable_id, :bigint
    remove_column :accounts, :sourceable_type, :string

    remove_index :transactions, name: "index_transactions_on_sourceable", column: [ :sourceable_type, :sourceable_id ]
    remove_column :transactions, :sourceable_id, :bigint
    remove_column :transactions, :sourceable_type, :string
  end
end
