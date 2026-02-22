class CreateSimplefinConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :simplefin_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :url
      t.timestamp :refreshed_at

      t.timestamps
    end

    add_index :simplefin_connections, :refreshed_at
  end
end
