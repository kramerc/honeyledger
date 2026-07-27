class AddDirectionOverriddenToTransactionSources < ActiveRecord::Migration[8.1]
  def change
    add_column :transaction_sources, :direction_overridden, :boolean, default: false, null: false
    add_index :transaction_sources, :direction_overridden,
              where: "direction_overridden",
              name: "index_transaction_sources_on_direction_overridden"
  end
end
