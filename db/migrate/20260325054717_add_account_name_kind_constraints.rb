class AddAccountNameKindConstraints < ActiveRecord::Migration[8.1]
  def change
    change_column_null :accounts, :name, false
    change_column_null :accounts, :kind, false

    add_index :accounts, [ :user_id, :kind, :name ], unique: true
  end
end
