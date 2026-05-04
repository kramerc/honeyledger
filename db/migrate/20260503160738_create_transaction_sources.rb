class CreateTransactionSources < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_sources do |t|
      t.references :transaction, null: false, foreign_key: true
      t.string :sourceable_type, null: false
      t.bigint :sourceable_id, null: false
      t.timestamps
    end

    add_index :transaction_sources, [ :sourceable_type, :sourceable_id ], unique: true, name: "index_transaction_sources_on_sourceable"
    add_index :transaction_sources, [ :transaction_id, :sourceable_type, :sourceable_id ], unique: true, name: "index_transaction_sources_on_transaction_and_sourceable"
  end
end
