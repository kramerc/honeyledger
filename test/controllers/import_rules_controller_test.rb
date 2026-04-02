require "test_helper"

class ImportRulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @import_rule = import_rules(:fixture_rule_one)
  end

  test "should get index" do
    get import_rules_url
    assert_response :success
  end

  test "should get new" do
    get new_import_rule_url
    assert_response :success
  end

  test "should create import_rule" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "New Pattern",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }
    end

    assert_redirected_to import_rules_path
  end

  test "should get edit" do
    get edit_import_rule_url(@import_rule)
    assert_response :success
  end

  test "should update import_rule" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: "Updated Pattern",
      priority: 5
    } }
    assert_redirected_to import_rules_path
    @import_rule.reload
    assert_equal "Updated Pattern", @import_rule.match_pattern
    assert_equal 5, @import_rule.priority
  end

  test "should destroy import_rule" do
    assert_difference("ImportRule.count", -1) do
      delete import_rule_url(@import_rule)
    end

    assert_redirected_to import_rules_path
  end

  test "should not access other users rules" do
    other_user = users(:two)
    other_account = Account.create!(user: other_user, currency: currencies(:usd), name: "Other Expense", kind: :expense)
    other_rule = ImportRule.create!(user: other_user, account: other_account, match_pattern: "Other")

    get edit_import_rule_url(other_rule)
    assert_response :not_found
  end

  test "should create import_rule as json" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "JSON Pattern",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :created
  end

  test "should update import_rule as json" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: "JSON Updated"
    } }, as: :json
    assert_response :ok
  end

  test "should destroy import_rule as json" do
    assert_difference("ImportRule.count", -1) do
      delete import_rule_url(@import_rule), as: :json
    end

    assert_response :no_content
  end

  test "should not update with invalid params" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: ""
    } }
    assert_response :unprocessable_entity
  end

  test "should not update with invalid params as json" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: ""
    } }, as: :json
    assert_response :unprocessable_entity
  end

  test "should not create rule with invalid params" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }
    end

    assert_response :unprocessable_entity
  end

  test "should not create rule with invalid params as json" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "should create rule with asset account as json" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Transfer",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :created
  end

  test "should get preview_apply" do
    get preview_apply_import_rules_url
    assert_response :success
  end

  test "should apply rules and redirect" do
    # Create an imported transaction that a rule would recategorize
    bank = accounts(:linked_asset)
    old_expense = Account.create!(user: @user, currency: currencies(:usd), name: "Old Category", kind: :expense)
    new_expense = Account.create!(user: @user, currency: currencies(:usd), name: "Apply Target", kind: :expense)

    Transaction.create!(
      user: @user,
      src_account: bank,
      dest_account: old_expense,
      amount_minor: 1000,
      currency: currencies(:usd),
      description: "APPLY_TEST_PATTERN",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_one)
    )

    ImportRule.create!(
      user: @user,
      account: new_expense,
      match_pattern: "APPLY_TEST_PATTERN",
      match_type: :exact,
      priority: 100
    )

    post apply_import_rules_url
    assert_redirected_to import_rules_path
    assert_match(/reassigned/, flash[:notice])
  end

  test "should apply with no changes" do
    post apply_import_rules_url
    assert_redirected_to import_rules_path
  end

  test "should get preview for a single rule" do
    get preview_import_rule_url(@import_rule)
    assert_response :success
  end

  test "preview_apply requires authentication" do
    sign_out @user
    get preview_apply_import_rules_url
    assert_response :redirect
  end

  test "apply requires authentication" do
    sign_out @user
    post apply_import_rules_url
    assert_response :redirect
  end

  test "preview requires authentication" do
    sign_out @user
    get preview_import_rule_url(@import_rule)
    assert_response :redirect
  end

  test "should create rule with asset account" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Transfer",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }
    end

    assert_redirected_to import_rules_path
  end
end
