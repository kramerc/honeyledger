class AddRemoteIdToCsvTransactions < ActiveRecord::Migration[8.1]
  def change
    # Nullable: nil means the import mapped no id column. Non-unique on
    # purpose — one export can carry a pending row and its posted replacement
    # under the same id, and re-imports share ids across imports by design.
    add_column :csv_transactions, :remote_id, :string
    add_index :csv_transactions, [ :import_id, :remote_id ], where: "remote_id IS NOT NULL"
  end
end
