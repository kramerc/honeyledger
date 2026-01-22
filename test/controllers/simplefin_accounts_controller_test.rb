require "test_helper"

class SimplefinAccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @simplefin_account = simplefin_accounts(:linked_one)
  end

  test "should link account" do
    account = accounts(:one)

    assert_difference "Transaction.count", 0 do
      post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { account_id: account.id } }
    end

    assert_redirected_to simplefin_connection_url
    @simplefin_account.reload
    assert_equal account, @simplefin_account.account
  end

  test "should unlink account" do
    # Ensure the account is linked first
    assert_not_nil @simplefin_account.account

    delete unlink_simplefin_account_url(@simplefin_account)

    assert_redirected_to simplefin_connection_url
    @simplefin_account.reload
    assert_nil @simplefin_account.account
  end
end
