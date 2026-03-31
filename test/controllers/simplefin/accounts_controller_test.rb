require "test_helper"

class Simplefin::AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @simplefin_account = simplefin_accounts(:linked_one)
  end

  test "should link account" do
    sf_account = simplefin_accounts(:unlinked_one)
    unlinked_account = accounts(:unlinked_liability)

    post link_simplefin_account_url(sf_account), params: { simplefin_account: { ledger_account_id: unlinked_account.id } }

    assert_redirected_to integrations_url
    unlinked_account.reload
    assert_equal sf_account, unlinked_account.sourceable
  end

  test "should enqueue TransactionImportJob when account is linked" do
    sf_account = simplefin_accounts(:unlinked_one)
    unlinked_account = accounts(:unlinked_liability)

    assert_enqueued_with(job: Simplefin::TransactionImportJob, args: [ { simplefin_account_id: sf_account.id } ]) do
      post link_simplefin_account_url(sf_account), params: { simplefin_account: { ledger_account_id: unlinked_account.id } }
    end
  end

  test "should unlink account" do
    assert_not_nil @simplefin_account.ledger_account

    delete unlink_simplefin_account_url(@simplefin_account)

    assert_redirected_to integrations_url
    @simplefin_account.reload
    assert_nil @simplefin_account.ledger_account
  end

  test "should reject link when ledger_account_id is blank" do
    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { ledger_account_id: "" } }

    assert_redirected_to integrations_url
    assert_equal "Please select an account to link.", flash[:alert]
  end

  test "should reject link when account does not belong to user" do
    other_user_account = accounts(:two)

    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { ledger_account_id: other_user_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Account not found.", flash[:alert]
  end

  test "should reject link when ledger account is already linked to another integration" do
    already_linked_account = accounts(:linked_asset)

    post link_simplefin_account_url(simplefin_accounts(:unlinked_one)), params: { simplefin_account: { ledger_account_id: already_linked_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Account is already linked to another integration.", flash[:alert]
  end

  test "should reject link when simplefin account is already linked to a different ledger account" do
    # linked_one is already linked to linked_asset via fixtures
    other_account = accounts(:unlinked_liability)

    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { ledger_account_id: other_account.id } }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account is already linked to another account.", flash[:alert]
  end

  test "should show error when link update fails" do
    unlinked_account = accounts(:unlinked_liability)

    Account.stub_any_instance :update, false do
      post link_simplefin_account_url(simplefin_accounts(:unlinked_one)), params: { simplefin_account: { ledger_account_id: unlinked_account.id } }

      assert_redirected_to integrations_url
      assert_match(/Failed to link SimpleFIN account/, flash[:alert])
    end
  end

  test "should show error when unlink fails" do
    assert_not_nil @simplefin_account.ledger_account

    Account.stub_any_instance :update, false do
      delete unlink_simplefin_account_url(@simplefin_account)

      assert_redirected_to integrations_url
      assert_match(/Failed to unlink SimpleFIN account/, flash[:alert])
    end
  end
end
