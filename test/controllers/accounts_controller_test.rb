require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    @account = accounts(:one)
  end

  test "should get index" do
    get accounts_url
    assert_response :success
  end

  test "should get new" do
    get new_account_url
    assert_response :success
  end

  test "should create account without opening balance" do
    assert_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "New Account",
          kind: "asset",
          currency_id: @account.currency_id
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_nil Account.last.opening_balance_transaction
  end

  test "should create account with no opening balance if zero" do
    assert_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "New Account with Zero Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_transaction_attributes: {
            amount_minor: 0,
            transacted_at: Time.current
          }
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_nil Account.last.opening_balance_transaction
  end

  test "should create account with opening balance" do
    assert_difference("Account.count", 2) do # Account + Opening Balance Account
      post accounts_url, params: {
        account: {
          name: "New Account with Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_transaction_attributes: {
            amount_minor: 50000,
            transacted_at: Time.current
          }
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_equal 50000, Account.last.opening_balance_transaction.amount_minor
  end

  test "should show account" do
    get account_url(@account)
    assert_response :success
  end

  test "should get edit" do
    get edit_account_url(@account)
    assert_response :success
  end

  test "should update account without opening balance" do
    patch account_url(@account), params: {
      account: {
        name: "Updated Name",
        kind: @account.kind,
        currency_id: @account.currency_id
      }
    }
    assert_redirected_to account_url(@account)

    @account.reload
    assert_equal "Updated Name", @account.name
  end

  test "should update account with opening balance" do
    patch account_url(@account), params: {
      account: {
        name: @account.name,
        kind: @account.kind,
        currency_id: @account.currency_id,
        opening_balance_transaction_attributes: {
          amount_minor: 10000,
          transacted_at: Time.current
        }
      }
    }
    assert_redirected_to account_url(@account)

    @account.reload
    assert_equal 10000, @account.opening_balance_transaction.amount_minor
  end

  test "should destroy account" do
    unused_account = Account.create!(
      user: users(:one),
      name: "Unused Account",
      kind: "asset",
      currency: currencies(:usd)
    )
    assert_difference("Account.count", -1) do
      delete account_url(unused_account)
    end

    assert_redirected_to accounts_url
  end
end
