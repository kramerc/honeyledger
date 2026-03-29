require "test_helper"

class Lunchflow::AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in @user
    @lunchflow_account = lunchflow_accounts(:unlinked_one)
  end

  test "should link account" do
    unlinked_account = accounts(:unlinked_liability)

    post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: unlinked_account.id } }

    assert_redirected_to integrations_url
    unlinked_account.reload
    assert_equal @lunchflow_account, unlinked_account.sourceable
  end

  test "should enqueue TransactionImportJob when account is linked" do
    unlinked_account = accounts(:unlinked_liability)

    assert_enqueued_with(job: TransactionImportJob, args: [ { lunchflow_account_id: @lunchflow_account.id } ]) do
      post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: unlinked_account.id } }
    end
  end

  test "should unlink account" do
    linked_lf_account = lunchflow_accounts(:linked_one)
    assert_not_nil linked_lf_account.ledger_account

    delete unlink_lunchflow_account_url(linked_lf_account)

    assert_redirected_to integrations_url
    linked_lf_account.reload
    assert_nil linked_lf_account.ledger_account
  end

  test "should reject link when ledger_account_id is blank" do
    post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: "" } }

    assert_redirected_to integrations_url
    assert_equal "Please select an account to link.", flash[:alert]
  end

  test "should reject link when ledger account is already linked to another integration" do
    already_linked_account = accounts(:linked_asset)

    post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: already_linked_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Account is already linked to another integration.", flash[:alert]
  end

  test "should reject link when lunchflow account is already linked to a different ledger account" do
    # linked_one is already linked to lunchflow_linked_asset via fixtures
    linked_lf_account = lunchflow_accounts(:linked_one)
    other_account = accounts(:unlinked_liability)

    post link_lunchflow_account_url(linked_lf_account), params: { lunchflow_account: { ledger_account_id: other_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account is already linked to another account.", flash[:alert]
  end

  test "should reject link when account does not belong to user" do
    other_user_account = accounts(:two)

    post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: other_user_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Account not found.", flash[:alert]
  end

  test "should show error when link fails validation" do
    unlinked_account = accounts(:unlinked_liability)

    Account.stub_any_instance :update, false do
      post link_lunchflow_account_url(@lunchflow_account), params: { lunchflow_account: { ledger_account_id: unlinked_account.id } }

      assert_redirected_to integrations_url
      assert_match(/Failed to link Lunch Flow account/, flash[:alert])
    end
  end

  test "should show error when unlink fails" do
    linked_lf_account = lunchflow_accounts(:linked_one)
    assert_not_nil linked_lf_account.ledger_account

    Account.stub_any_instance :update, false do
      delete unlink_lunchflow_account_url(linked_lf_account)

      assert_redirected_to integrations_url
      assert_match(/Failed to unlink Lunch Flow account/, flash[:alert])
    end
  end
end
