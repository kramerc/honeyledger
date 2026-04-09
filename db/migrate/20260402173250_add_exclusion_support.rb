class AddExclusionSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :excluded_at, :datetime
    add_index :transactions, :excluded_at, where: "excluded_at IS NOT NULL", name: "index_transactions_on_excluded_at"

    add_column :import_rules, :exclude, :boolean, default: false, null: false
    change_column_null :import_rules, :account_id, true
  end
end
