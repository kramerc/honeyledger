class CreateCsvTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_transactions do |t|
      t.references :import, null: false, foreign_key: { to_table: :csv_imports }
      t.integer :row_index, null: false
      t.datetime :transacted_at, null: false
      t.datetime :posted_at
      t.string :description, null: false, default: ""
      t.integer :amount_minor, null: false
      t.datetime :synced_at
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end

    add_index :csv_transactions, [ :import_id, :row_index ], unique: true
    add_index :csv_transactions, :synced_at
  end
end
