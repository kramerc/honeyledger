class CreateImportRules < ActiveRecord::Migration[8.1]
  def change
    create_table :import_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :match_pattern, null: false
      t.integer :match_type, null: false, default: 0
      t.integer :priority, null: false, default: 0

      t.timestamps
    end

    add_index :import_rules, [ :user_id, :match_pattern, :match_type ], unique: true
  end
end
