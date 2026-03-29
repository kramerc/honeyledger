class CreateLunchflowAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :lunchflow_accounts do |t|
      t.references :connection, null: false, foreign_key: { to_table: :lunchflow_connections }
      t.integer :remote_id, null: false
      t.string :name
      t.string :institution_name
      t.string :institution_logo
      t.string :provider
      t.string :currency
      t.string :status
      t.string :balance

      t.timestamps
    end

    add_index :lunchflow_accounts, [ :connection_id, :remote_id ], unique: true
  end
end
