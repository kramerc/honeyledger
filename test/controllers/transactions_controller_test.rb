require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @transaction = transactions(:one)
  end

  test "should get index" do
    get transactions_url
    assert_response :success
  end

  test "should filter transactions by account" do
    account = accounts(:asset_account)
    get transactions_url, params: { account_id: account.id }
    assert_response :success
    # Filtered results should include transactions involving the asset_account
    assert_match account.name, response.body
  end

  test "should return all transactions when no account filter" do
    get transactions_url
    assert_response :success
    # Without filter, both fixture transactions should appear
    assert_match transactions(:one).description, response.body
    assert_match transactions(:two).description, response.body
  end

  test "should get new" do
    get new_transaction_url
    assert_response :success
  end

  test "should create transaction" do
    assert_difference("Transaction.count") do
      post transactions_url, params: { transaction: { transacted_at: @transaction.transacted_at, category_id: @transaction.category_id, src_account_id: @transaction.src_account_id, dest_account_id: @transaction.dest_account_id, description: @transaction.description, amount_minor: @transaction.amount_minor, currency_id: @transaction.currency_id, fx_amount_minor: @transaction.fx_amount_minor, fx_currency_id: @transaction.fx_currency_id, notes: @transaction.notes } }
    end

    assert_redirected_to transaction_url(Transaction.last)
  end

  test "should show transaction" do
    get transaction_url(@transaction)
    assert_response :success
  end

  test "should get edit" do
    get edit_transaction_url(@transaction)
    assert_response :success
  end

  test "should update transaction" do
    patch transaction_url(@transaction), params: { transaction: { transacted_at: @transaction.transacted_at, category_id: @transaction.category_id, src_account_id: @transaction.src_account_id, dest_account_id: @transaction.dest_account_id, description: @transaction.description, amount_minor: @transaction.amount_minor, currency_id: @transaction.currency_id, fx_amount_minor: @transaction.fx_amount_minor, fx_currency_id: @transaction.fx_currency_id, notes: @transaction.notes } }
    assert_redirected_to transaction_url(@transaction)
  end

  test "should destroy transaction" do
    assert_difference("Transaction.count", -1) do
      delete transaction_url(@transaction)
    end

    assert_redirected_to transactions_url
  end
end
