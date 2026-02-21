class CreateSimplefinAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :simplefin_accounts do |t|
      t.references :account, null: true, foreign_key: true, index: { unique: true }
      t.references :simplefin_connection, null: false, foreign_key: true
      t.string :remote_id
      t.jsonb :org
      t.string :name
      t.string :currency
      t.string :balance
      t.string :available_balance
      t.timestamp :balance_date
      t.jsonb :extra

      t.timestamps
    end
  end
end
