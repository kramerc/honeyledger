class MakeAccountNameUniquenessCaseInsensitive < ActiveRecord::Migration[8.1]
  def change
    remove_index :accounts, [ :user_id, :kind, :name ], unique: true
    add_index :accounts,
              "user_id, kind, LOWER(name)",
              unique: true,
              name: "index_accounts_on_user_id_kind_lower_name"
  end
end
