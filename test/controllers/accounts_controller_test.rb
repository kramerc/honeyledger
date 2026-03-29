require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
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

  test "should get new with an unlinked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_response :success
  end

  test "should redirect on new with a SimpleFIN account but no connection" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    @user.simplefin_connection = nil
    @user.save!

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to new_simplefin_connection_url
    assert_equal "Cannot import SimpleFIN account without a connection.", flash[:alert]
  end

  test "should redirect on new with linked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:linked_one)

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account already linked to another account.", flash[:alert]
  end

  test "should redirect on new with a SimpleFIN account not found" do
    get new_account_url, params: { simplefin_account_id: "invalid" }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  test "should on new scope finding a SimpleFIN account to the current user" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    simplefin_account.update!(connection: simplefin_connections(:two)) # Has different user

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
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
          opening_balance_amount: "0",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_nil Account.last.opening_balance_transaction
  end

  test "should create account with opening balance" do
    # Account + Opening Balance Account
    assert_difference("Account.count", 2) do
      post accounts_url, params: {
        account: {
          name: "New Account with Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_amount: "500.00",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    new_account = Account.last
    assert_redirected_to account_url(new_account)
    assert_equal 50000, new_account.opening_balance_transaction.amount_minor
  end

  test "should create linked to a SimpleFIN account when given" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    assert_difference("Account.count", 1) do
      post accounts_url, params: {
        account: {
          name: "New Account",
          kind: "asset",
          currency_id: @account.currency_id
        },
        simplefin_account_id: simplefin_account.id
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_equal simplefin_account, Account.last.sourceable
  end

  test "should redirect on create with a SimpleFIN account but no connection" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    @user.simplefin_connection = nil
    @user.save!

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to new_simplefin_connection_url
    assert_equal "Cannot import SimpleFIN account without a connection.", flash[:alert]
  end

  test "should redirect on create when given a linked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:linked_one)

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account already linked to another account.", flash[:alert]
  end

  test "should redirect on create when given a SimpleFIN account not found" do
    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: "invalid"
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  test "should on create scope finding a SimpleFIN account to the current user" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    simplefin_account.update!(connection: simplefin_connections(:two)) # Has different user

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  # Lunch Flow import tests

  test "should get new with an unlinked Lunch Flow account" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_response :success
    assert_select "input[name='account[name]'][value=?]", lunchflow_account.name
  end

  test "should redirect on new with a Lunch Flow account but no connection" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    @user.lunchflow_connection = nil
    @user.save!

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to new_lunchflow_connection_url
    assert_equal "Cannot import Lunch Flow account without a connection.", flash[:alert]
  end

  test "should redirect on new with linked Lunch Flow account" do
    lunchflow_account = lunchflow_accounts(:linked_one)

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account already linked to another account.", flash[:alert]
  end

  test "should redirect on new with a Lunch Flow account not found" do
    get new_account_url, params: { lunchflow_account_id: "invalid" }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account to import was not found.", flash[:alert]
  end

  test "should on new scope finding a Lunch Flow account to the current user" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.update!(connection: lunchflow_connections(:two))

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account to import was not found.", flash[:alert]
  end

  test "should validate on create" do
    assert_no_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "",
          kind: "asset",
          currency_id: @account.currency_id
        }
      }
    end

    assert_response :unprocessable_entity
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

  test "should update account with positive opening balance" do
    patch account_url(@account), params: {
      account: {
        name: @account.name,
        kind: @account.kind,
        currency_id: @account.currency_id,
        opening_balance_amount: "100.00",
        opening_balance_transacted_at: Time.current
      }
    }
    assert_redirected_to account_url(@account)

    @account.reload
    assert_equal 10000, @account.opening_balance_transaction.amount_minor
  end

  test "should create account with negative opening balance" do
    # Account + Opening Balance Account
    assert_difference("Account.count", 2) do
      post accounts_url, params: {
        account: {
          name: "New Account with Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_amount: "-500.00",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    new_account = Account.last
    assert_redirected_to account_url(new_account)
    assert_equal 50000, new_account.opening_balance_transaction.amount_minor, "negative opening balance is persisted as absolute value"
    assert new_account.opening_balance_transaction.src_account.real?, "src_account should be the real account for a negative opening balance"
  end

  test "should validate on update" do
    assert_no_difference("Account.count") do
      patch account_url(@account), params: {
        account: {
          name: ""
        }
      }
    end

    assert_response :unprocessable_entity
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
