require "test_helper"

class Lunchflow::TransactionTest < ActiveSupport::TestCase
  setup do
    @lunchflow_transaction = lunchflow_transactions(:transaction_one)
  end

  test "belongs to account" do
    assert_equal lunchflow_accounts(:linked_one), @lunchflow_transaction.account
  end
end
