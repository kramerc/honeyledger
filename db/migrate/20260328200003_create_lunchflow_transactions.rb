class CreateLunchflowTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :lunchflow_transactions do |t|
      t.references :account, null: false, foreign_key: { to_table: :lunchflow_accounts }
      t.string :remote_id
      t.string :amount
      t.string :currency
      t.string :description
      t.string :merchant
      t.boolean :pending
      t.date :date
      t.timestamp :synced_at

      t.timestamps
    end

    add_index :lunchflow_transactions, :synced_at
    add_index :lunchflow_transactions, [ :account_id, :remote_id ], unique: true
  end
end
