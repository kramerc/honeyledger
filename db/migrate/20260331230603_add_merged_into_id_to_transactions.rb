class AddMergedIntoIdToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :merged_into, null: true, foreign_key: { to_table: :transactions }
  end
end
