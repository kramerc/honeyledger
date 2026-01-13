class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.integer :kind
      t.string :currency, default: "USD"

      t.timestamps
    end
  end
end
