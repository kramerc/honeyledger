class CreateCurrencies < ActiveRecord::Migration[8.1]
  def change
    create_table :currencies do |t|
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.string :symbol, null: false
      t.string :code, null: false, limit: 10
      t.integer :decimal_places, null: false, default: 2
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :currencies, :kind
    add_index :currencies, :code, unique: true
  end
end
