class CreateLunchflowConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :lunchflow_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :api_key, null: false
      t.string :error
      t.timestamp :refreshed_at

      t.timestamps
    end

    add_index :lunchflow_connections, :refreshed_at
  end
end
