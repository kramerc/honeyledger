class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.jsonb :column_mappings, null: false, default: {}
      t.datetime :parsed_at
      t.datetime :imported_at
      t.text :error

      t.timestamps
    end

    add_index :csv_imports, [ :account_id, :created_at ]
  end
end
