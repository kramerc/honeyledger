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
    assert_match transactions(:one).description, response.body # src_account is asset_account
    assert_match transactions(:two).description, response.body # dest_account is asset_account
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

  test "should get inline_edit" do
    get inline_edit_transaction_url(@transaction)
    assert_response :success
  end

  test "should create transaction with turbo_stream" do
    assert_difference("Transaction.count") do
      post transactions_url,
        params: { transaction: {
          transacted_at: @transaction.transacted_at,
          src_account_id: @transaction.src_account_id,
          dest_account_id: @transaction.dest_account_id,
          description: "New transaction",
          amount_display: "50.00"
        } },
        as: :turbo_stream
    end

    assert_response :success
  end

  test "should update transaction with turbo_stream" do
    patch transaction_url(@transaction),
      params: { transaction: {
        description: "Updated description",
        amount_display: "100.00"
      } },
      as: :turbo_stream

    assert_response :success
    @transaction.reload
    assert_equal "Updated description", @transaction.description
  end

  test "should destroy transaction with turbo_stream" do
    assert_difference("Transaction.count", -1) do
      delete transaction_url(@transaction), as: :turbo_stream
    end

    assert_response :success
  end

  test "should create transaction with category_name" do
    assert_difference([ "Transaction.count", "Category.count" ]) do
      post transactions_url,
        params: { transaction: {
          transacted_at: @transaction.transacted_at,
          src_account_id: @transaction.src_account_id,
          dest_account_id: @transaction.dest_account_id,
          description: "Test transaction",
          amount_display: "25.50",
          category_name: "New Test Category"
        } }
    end

    assert_equal "New Test Category", Transaction.last.category.name
  end

  test "should update transaction with existing category_name" do
    existing_category = categories(:one)

    patch transaction_url(@transaction),
      params: { transaction: {
        category_name: existing_category.name
      } }

    @transaction.reload
    assert_equal existing_category.id, @transaction.category_id
  end

  test "should handle validation errors with turbo_stream on create" do
    post transactions_url,
      params: { transaction: {
        description: "Invalid transaction"
        # Missing required fields
      } },
      as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "should handle validation errors with turbo_stream on update" do
    patch transaction_url(@transaction),
      params: { transaction: {
        src_account_id: nil  # Make it invalid
      } },
      as: :turbo_stream

    assert_response :unprocessable_entity
  end
end
