class AddUniqueIndexToAccountNames < ActiveRecord::Migration[8.1]
  def change
    add_index :accounts, [ :user_id, :name, :kind ], unique: true
  end
end
