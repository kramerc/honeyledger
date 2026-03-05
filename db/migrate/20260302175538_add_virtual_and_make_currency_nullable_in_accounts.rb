class AddVirtualAndMakeCurrencyNullableInAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :virtual, :boolean, null: false, default: false
    change_column_null :accounts, :currency_id, true
  end
end
