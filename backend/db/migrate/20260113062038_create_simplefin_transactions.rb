class CreateSimplefinTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :simplefin_transactions do |t|
      t.references :simplefin_account, null: false, foreign_key: true
      t.string :remote_id
      t.timestamp :posted
      t.string :amount
      t.string :description
      t.timestamp :transacted_at
      t.boolean :pending
      t.jsonb :extra

      t.timestamp :synced_at

      t.timestamps
    end

    add_index :simplefin_transactions, :synced_at
  end
end
