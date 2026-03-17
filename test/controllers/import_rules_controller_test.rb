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

  test "should not create rule with invalid params as json" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Invalid",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "should not create rule with asset account" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Invalid",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }
    end

    assert_response :unprocessable_entity
  end
end
