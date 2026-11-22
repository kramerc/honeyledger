require "test_helper"

class Blockchain::AccountsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in_as(@user)
    @blockchain_account = blockchain_accounts(:xpub_wallet_btc)
    @ledger_account = @user.accounts.create!(name: "Hardware wallet", kind: :asset, currency: currencies(:btc))
  end

  test "link attaches the account and enqueues the import" do
    assert_enqueued_with(job: Blockchain::ImportTransactionsJob, args: [ { blockchain_account_id: @blockchain_account.id } ]) do
      post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: @ledger_account.id } }
    end

    assert_redirected_to integrations_url
    assert_equal @ledger_account, @blockchain_account.reload.ledger_account
  end

  test "link requires a ledger account" do
    post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: "" } }

    assert_redirected_to integrations_url
    assert_equal "Please select an account to link.", flash[:alert]
  end

  test "link refuses an account the user does not own" do
    post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: accounts(:two).id } }

    assert_redirected_to integrations_url
    assert_equal "Account not found.", flash[:alert]
  end

  test "link refuses an account in another currency" do
    usd_account = @user.accounts.create!(name: "Crypto (USD)", kind: :asset, currency: currencies(:usd))

    post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: usd_account.id } }

    assert_redirected_to integrations_url
    assert_equal "Link the wallet to an account in BTC.", flash[:alert]
    assert_empty @blockchain_account.reload.ledger_accounts
  end

  test "link refuses a second ledger account" do
    AccountSource::Attach.call(account: @ledger_account, sourceable: @blockchain_account)
    other = @user.accounts.create!(name: "Other wallet", kind: :asset, currency: currencies(:btc))

    post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: other.id } }

    assert_redirected_to integrations_url
    assert_equal "Wallet account is already linked to another account.", flash[:alert]
  end

  test "link reports a source attached elsewhere concurrently" do
    AccountSource::Attach.stub :call, ->(**) { raise AccountSource::Attach::MismatchedAccount } do
      post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: @ledger_account.id } }
    end

    assert_equal "Wallet account is already linked to another account.", flash[:alert]
  end

  test "unlink detaches the account" do
    AccountSource::Attach.call(account: @ledger_account, sourceable: @blockchain_account)

    delete unlink_blockchain_account_url(@blockchain_account)

    assert_redirected_to integrations_url
    assert_empty @blockchain_account.reload.ledger_accounts
  end

  test "cannot link another user's wallet account" do
    sign_in_as(users(:two))

    post link_blockchain_account_url(@blockchain_account), params: { blockchain_account: { ledger_account_id: @ledger_account.id } }

    assert_response :not_found
  end
end
