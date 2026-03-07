class AddBalanceMinorToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :balance_minor, :bigint

    reversible do |dir|
      dir.up do
        Account.reset_column_information
        Account.real.each(&:reset_balance)
      end
    end
  end
end
