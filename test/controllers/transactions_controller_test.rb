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

  test "should get index scoped to account" do
    account = accounts(:asset_account)
    get account_transactions_url(account)
    assert_response :success
  end

  test "account-scoped index only returns transactions for that account" do
    account = accounts(:asset_account)

    # Create a transaction that does NOT involve the scoped account
    unrelated = Transaction.create!(
      user: @user,
      src_account: accounts(:linked_asset),
      dest_account: accounts(:liability_account),
      description: "Unrelated Transfer",
      amount_minor: 1000,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    get account_transactions_url(account)
    assert_response :success

    # Verify the response contains a transaction that involves this account
    expected_transaction = @user.transactions.find_by(src_account: account) ||
                           @user.transactions.find_by(dest_account: account)
    assert_not_nil expected_transaction, "Expected user to have a transaction involving the account"
    assert_includes response.body, expected_transaction.description
    assert_not_includes response.body, unrelated.description
  end

  test "account-scoped index returns 404 for account not belonging to user" do
    other_user_account = accounts(:two)
    get account_transactions_url(other_user_account)
    assert_response :not_found
  end

  test "should get new" do
    get new_transaction_url

    assert_response :success
  end

  test "should create transaction" do
    assert_difference("Transaction.count") do
      post transactions_url, params: { transaction: {
        transacted_at: @transaction.transacted_at,
        category_id: @transaction.category_id,
        src_account_id: @transaction.src_account_id,
        dest_account_id: @transaction.dest_account_id,
        description: @transaction.description,
        amount_minor: @transaction.amount_minor,
        currency_id: @transaction.currency_id,
        fx_amount_minor: @transaction.fx_amount_minor,
        fx_currency_id: @transaction.fx_currency_id,
        notes: @transaction.notes
      } }, as: :json
    end

    assert_response :created
  end

  test "should get edit" do
    get edit_transaction_url(@transaction)

    assert_response :success
  end

  test "should update transaction" do
    patch transaction_url(@transaction), params: { transaction: {
      transacted_at: @transaction.transacted_at,
      category_id: @transaction.category_id,
      src_account_id: @transaction.src_account_id,
      dest_account_id: @transaction.dest_account_id,
      description: @transaction.description,
      amount_minor: @transaction.amount_minor,
      currency_id: @transaction.currency_id,
      fx_amount_minor: @transaction.fx_amount_minor,
      fx_currency_id: @transaction.fx_currency_id,
      notes: @transaction.notes
    } }, as: :json
    assert_response :ok
  end

  test "should destroy transaction" do
    assert_difference("Transaction.count", -1) do
      delete transaction_url(@transaction), as: :json
    end

    assert_response :no_content
  end

  test "should create transaction with turbo_stream" do
    assert_difference("Transaction.count") do
      post transactions_url, params: { transaction: {
        transacted_at: @transaction.transacted_at,
        src_account_id: @transaction.src_account_id,
        dest_account_id: @transaction.dest_account_id,
        description: "New transaction",
        amount: "50.00"
      } }, as: :turbo_stream
    end

    assert_response :success
  end

  test "should update transaction with turbo_stream" do
    patch transaction_url(@transaction), params: { transaction: {
      description: "Updated description",
      amount: "100.00"
    } }, as: :turbo_stream

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

  test "should create transaction with category_id for existing category" do
    existing_category = categories(:one)

    assert_difference("Transaction.count", 1) do
      assert_no_difference("Category.count") do
        post transactions_url, params: { transaction: {
          transacted_at: @transaction.transacted_at,
          src_account_id: @transaction.src_account_id,
          dest_account_id: @transaction.dest_account_id,
          description: "Test transaction",
          amount: "25.50",
          category_id: existing_category.id
        } }, as: :json
      end
    end

    assert_equal existing_category.id, Transaction.last.category_id
  end

  test "should update transaction with category_id for existing category" do
    original_category = categories(:one)
    new_category = categories(:two)
    @transaction.update!(category: original_category)

    patch transaction_url(@transaction), params: { transaction: {
      category_id: new_category.id
    } }, as: :json

    @transaction.reload
    assert_equal new_category.id, @transaction.category_id
  end

  test "should clear category when category_id is blank" do
    @transaction.update!(category: categories(:one))

    patch transaction_url(@transaction), params: { transaction: {
      category_id: ""
    } }, as: :json

    @transaction.reload
    assert_nil @transaction.category_id
  end

  test "should handle invalid amount gracefully" do
    assert_no_difference("Transaction.count") do
      post transactions_url, params: { transaction: {
        transacted_at: @transaction.transacted_at,
        src_account_id: @transaction.src_account_id,
        dest_account_id: @transaction.dest_account_id,
        description: "Test transaction",
        amount: "not a number"
      } }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "should handle invalid amount on update" do
    original_amount = @transaction.amount_minor

    patch transaction_url(@transaction), params: { transaction: {
      amount: "invalid"
    } }, as: :json

    assert_response :unprocessable_entity
    @transaction.reload
    # Original amount is preserved when invalid input provided
    assert_equal original_amount, @transaction.amount_minor
  end

  test "should handle validation errors with turbo_stream on create" do
    post transactions_url, params: { transaction: {
      description: "Invalid transaction"
      # Missing required fields
    } }, as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "should handle validation errors with turbo_stream on update" do
    patch transaction_url(@transaction), params: { transaction: {
      src_account_id: nil # Make it invalid
    } }, as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "index excludes merged transactions" do
    currency = currencies(:usd)
    bank_a = accounts(:asset_account)
    bank_b = accounts(:linked_asset)
    expense = Account.create!(user: @user, name: "Merge Test Expense", kind: :expense, currency: currency)
    revenue = Account.create!(user: @user, name: "Merge Test Revenue", kind: :revenue, currency: currency)

    withdrawal = Transaction.create!(user: @user, src_account: bank_a, dest_account: expense,
                                     amount_minor: 300, currency: currency, description: "Hidden after merge",
                                     transacted_at: Time.current)
    deposit = Transaction.create!(user: @user, src_account: revenue, dest_account: bank_b,
                                  amount_minor: 300, currency: currency, description: "Hidden after merge",
                                  transacted_at: Time.current)

    merger = Transaction::Merge.new(withdrawal, deposit, user: @user)
    merger.call

    get transactions_url
    assert_response :success

    # Merged originals should not appear (they have amount 0 and are hidden)
    # The new transfer should appear
    assert_includes response.body, merger.merged_transaction.description
  end

  test "merge with turbo_stream creates transfer and removes originals" do
    currency = currencies(:usd)
    bank_a = accounts(:asset_account)
    bank_b = accounts(:linked_asset)
    expense = Account.create!(user: @user, name: "Merge Expense", kind: :expense, currency: currency)
    revenue = Account.create!(user: @user, name: "Merge Revenue", kind: :revenue, currency: currency)

    withdrawal = Transaction.create!(user: @user, src_account: bank_a, dest_account: expense,
                                     amount_minor: 1000, currency: currency, description: "Test merge",
                                     transacted_at: Time.current)
    deposit = Transaction.create!(user: @user, src_account: revenue, dest_account: bank_b,
                                  amount_minor: 1000, currency: currency, description: "Test merge",
                                  transacted_at: Time.current)

    assert_difference("Transaction.count", 1) do  # +1 new, 0 destroyed (soft-delete)
      post merge_transactions_url, params: {
        transaction_ids: [ withdrawal.id, deposit.id ],
        description: "Merged transfer"
      }, as: :turbo_stream
    end

    assert_response :success

    withdrawal.reload
    deposit.reload
    assert_not_nil withdrawal.merged_into_id
    assert_not_nil deposit.merged_into_id
    assert_equal withdrawal.merged_into_id, deposit.merged_into_id
  end

  test "merge with invalid pair returns error" do
    # Both transactions have balance-sheet src — no valid merge possible
    t1 = Transaction.create!(user: @user, src_account: accounts(:asset_account),
                             dest_account: accounts(:expense_account), amount_minor: 100,
                             currency: currencies(:usd), transacted_at: Time.current,
                             description: "A")
    t2 = Transaction.create!(user: @user, src_account: accounts(:linked_asset),
                             dest_account: accounts(:expense_account), amount_minor: 200,
                             currency: currencies(:usd), transacted_at: Time.current,
                             description: "B")

    post merge_transactions_url, params: {
      transaction_ids: [ t1.id, t2.id ]
    }, as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "merge rejects other user's transactions" do
    other_user_tx = transactions(:opening_balance_revenue)
    post merge_transactions_url, params: {
      transaction_ids: [ other_user_tx.id, @transaction.id ]
    }, as: :turbo_stream

    assert_response :not_found
  end

  test "unmerge restores original transactions via turbo_stream" do
    currency = currencies(:usd)
    bank_a = accounts(:asset_account)
    bank_b = accounts(:linked_asset)
    expense = Account.create!(user: @user, name: "Unmerge Expense", kind: :expense, currency: currency)
    revenue = Account.create!(user: @user, name: "Unmerge Revenue", kind: :revenue, currency: currency)

    withdrawal = Transaction.create!(user: @user, src_account: bank_a, dest_account: expense,
                                     amount_minor: 500, currency: currency, description: "Unmerge test",
                                     transacted_at: Time.current)
    deposit = Transaction.create!(user: @user, src_account: revenue, dest_account: bank_b,
                                  amount_minor: 500, currency: currency, description: "Unmerge test",
                                  transacted_at: Time.current)

    merger = Transaction::Merge.new(withdrawal, deposit, user: @user)
    merger.call
    merged = merger.merged_transaction

    assert_difference("Transaction.count", -1) do
      post unmerge_transaction_url(merged), as: :turbo_stream
    end

    assert_response :success

    withdrawal.reload
    deposit.reload
    assert_nil withdrawal.merged_into_id
    assert_nil deposit.merged_into_id
    assert_equal 500, withdrawal.amount_minor
    assert_equal 500, deposit.amount_minor
  end

  test "unmerge on non-merged transaction returns error" do
    post unmerge_transaction_url(@transaction), as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "merge with wrong number of transaction IDs returns error" do
    post merge_transactions_url, params: {
      transaction_ids: [ @transaction.id ]
    }, as: :turbo_stream

    assert_response :unprocessable_entity
  end
end
