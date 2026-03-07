class AddBalanceToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance_minor, :integer
  end
end
