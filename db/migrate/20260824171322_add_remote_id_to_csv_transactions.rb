class AddRemoteIdToCsvTransactions < ActiveRecord::Migration[8.1]
  def change
    # Nullable: nil means the import mapped no id column. Non-unique on
    # purpose — one export can carry a pending row and its posted replacement
    # under the same id, and re-imports share ids across imports by design.
    # The index leads with remote_id because the import job looks a row up by
    # its id across every other import into the same ledger account.
    add_column :csv_transactions, :remote_id, :string
    add_index :csv_transactions, [ :remote_id, :import_id ], where: "remote_id IS NOT NULL"
  end
end
