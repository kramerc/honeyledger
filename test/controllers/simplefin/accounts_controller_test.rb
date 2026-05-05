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
    assert_includes sf_account.ledger_accounts, unlinked_account
  end

  test "should enqueue ImportTransactionsJob when account is linked" do
    sf_account = simplefin_accounts(:unlinked_one)
    unlinked_account = accounts(:unlinked_liability)

    assert_enqueued_with(job: Simplefin::ImportTransactionsJob, args: [ { simplefin_account_id: sf_account.id } ]) do
      post link_simplefin_account_url(sf_account), params: { simplefin_account: { ledger_account_id: unlinked_account.id } }
    end
  end

  test "should unlink account" do
    assert_not_nil @simplefin_account.ledger_account

    delete unlink_simplefin_account_url(@simplefin_account)

    assert_redirected_to integrations_url
    @simplefin_account.reload
    assert_nil @simplefin_account.ledger_account
    assert_empty @simplefin_account.ledger_accounts
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

  test "allows linking a ledger account that already has a different integration" do
    multi_sourced = accounts(:linked_asset)
    sf_to_add = simplefin_accounts(:unlinked_one)

    assert_difference -> { multi_sourced.account_sources.count }, 1 do
      post link_simplefin_account_url(sf_to_add), params: { simplefin_account: { ledger_account_id: multi_sourced.id } }
    end
    assert_redirected_to integrations_url
    assert_includes sf_to_add.ledger_accounts, multi_sourced
  end

  test "should reject link when simplefin account is already linked to a different ledger account" do
    # linked_one is already linked to linked_asset via fixtures
    other_account = accounts(:unlinked_liability)

    post link_simplefin_account_url(@simplefin_account), params: { simplefin_account: { ledger_account_id: other_account.id } }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account is already linked to another account.", flash[:alert]
  end

  test "rescues a concurrent-link race and surfaces the already-linked alert" do
    sf_account = simplefin_accounts(:unlinked_one)
    unlinked_account = accounts(:unlinked_liability)

    AccountSource::Attach.stub :call, ->(*) { raise AccountSource::Attach::MismatchedAccount, "race" } do
      post link_simplefin_account_url(sf_account), params: { simplefin_account: { ledger_account_id: unlinked_account.id } }
    end

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account is already linked to another account.", flash[:alert]
  end
end
