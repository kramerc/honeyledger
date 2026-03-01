require "test_helper"

class Simplefin::TransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)

    @bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Test Bank Account",
      kind: :asset
    )

    @connection = simplefin_connections(:one)

    @account = Simplefin::Account.create!(
      connection: @connection,
      ledger_account: @bank_account,
      remote_id: "acc_test",
      name: "Test Account",
      currency: "USD",
      balance: "1000.00"
    )
  end
end
