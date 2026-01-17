class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :sourceable, polymorphic: true, null: true

      t.references :parent_transaction, null: true, foreign_key: { to_table: :transactions }
      t.references :category, null: true, foreign_key: true

      t.references :src_account, null: false, foreign_key: { to_table: :accounts }
      t.references :dest_account, null: false, foreign_key: { to_table: :accounts }

      t.string :description, null: false, default: ""
      t.integer :amount_minor, null: false, default: 0
      t.references :currency, null: false, foreign_key: true

      t.integer :fx_amount_minor, null: true
      t.references :fx_currency, null: true, foreign_key: { to_table: :currencies }

      t.text :notes, null: false, default: ""

      t.timestamp :transacted_at, null: false
      t.timestamp :cleared_at, null: true
      t.timestamp :reconciled_at, null: true
      t.timestamp :synced_at, null: true

      t.boolean :split, null: false, default: false
      t.boolean :opening_balance, null: false, default: false

      t.timestamps
    end

    add_index :transactions, [ :user_id, :transacted_at ]  # date ranges, sorting
    add_index :transactions, [ :user_id, :split ]          # filtering splits per user
  end
end
