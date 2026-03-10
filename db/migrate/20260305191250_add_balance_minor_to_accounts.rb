class AddBalanceMinorToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance_minor, :bigint
  end
end
