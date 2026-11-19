class AddBalanceChangedAtToLunchflowAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :lunchflow_accounts, :balance_changed_at, :datetime
  end
end
