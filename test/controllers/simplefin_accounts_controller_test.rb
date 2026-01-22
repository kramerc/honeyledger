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

    assert_no_difference "Transaction.count" do
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

  test "should reject link when account_id is blank" do
    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { account_id: "" } }

    assert_redirected_to simplefin_connection_url
    assert_equal "Please select an account to link.", flash[:alert]
  end

  test "should reject link when account does not belong to user" do
    other_user_account = accounts(:two)

    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { account_id: other_user_account.id } }

    assert_redirected_to simplefin_connection_url
    assert_equal "Account not found.", flash[:alert]
  end

  test "should show error when link fails validation" do
    # Pre-create a SimplefinAccount linked to the target account to trigger the uniqueness validation
    SimplefinAccount.create!(
      simplefin_connection: @simplefin_account.simplefin_connection,
      account: accounts(:asset_account),
      remote_id: "test_remote_id",
      name: "Test Account",
      currency: "USD"
    )

    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { account_id: accounts(:asset_account).id } }

    assert_redirected_to simplefin_connection_url
    assert_match(/Failed to link SimpleFIN account/, flash[:alert])
  end

  test "should show error when unlink fails" do
    # Ensure the account is linked first
    assert_not_nil @simplefin_account.account

    # Override the update method to simulate failure
    SimplefinAccount.class_eval do
      alias_method :original_update, :update
      define_method(:update) do |*args|
        errors.add(:base, "Database error")
        false
      end
    end

    delete unlink_simplefin_account_url(@simplefin_account)

    assert_redirected_to simplefin_connection_url
    assert_match(/Failed to unlink SimpleFIN account/, flash[:alert])
  ensure
    # Restore the original method
    SimplefinAccount.class_eval do
      alias_method :update, :original_update
      remove_method :original_update
    end
  end
end
