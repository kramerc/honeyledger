class CreateAccountSources < ActiveRecord::Migration[8.1]
  def change
    create_table :account_sources do |t|
      t.references :account, null: false, foreign_key: true
      t.string :sourceable_type, null: false
      t.bigint :sourceable_id, null: false
      t.timestamps
    end

    add_index :account_sources, [ :sourceable_type, :sourceable_id ], unique: true, name: "index_account_sources_on_sourceable"
    add_index :account_sources, [ :account_id, :sourceable_type, :sourceable_id ], unique: true, name: "index_account_sources_on_account_and_sourceable"
  end
end
