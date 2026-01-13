class CreateSimplefinConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :simplefin_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url

      t.timestamps
    end
  end
end
