class AddAccountErrorsToSimplefinConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :simplefin_connections, :account_errors, :string, array: true, default: [], null: false
  end
end
