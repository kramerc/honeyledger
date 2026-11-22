# Minor-unit amounts move to numeric(78, 0) so 18-decimal currencies (ETH and
# most ERC-20 tokens) fit exactly: 78 digits covers any unsigned 256-bit value.
class WidenMinorUnitColumns < ActiveRecord::Migration[8.1]
  def up
    change_column :transactions, :amount_minor, :decimal, precision: 78, scale: 0, default: 0, null: false
    change_column :transactions, :fx_amount_minor, :decimal, precision: 78, scale: 0
    change_column :csv_transactions, :amount_minor, :decimal, precision: 78, scale: 0, null: false
    change_column :accounts, :balance_minor, :decimal, precision: 78, scale: 0
  end

  # Fails if any stored value no longer fits the narrower type.
  def down
    change_column :transactions, :amount_minor, :integer, default: 0, null: false
    change_column :transactions, :fx_amount_minor, :integer
    change_column :csv_transactions, :amount_minor, :integer, null: false
    change_column :accounts, :balance_minor, :bigint
  end
end
