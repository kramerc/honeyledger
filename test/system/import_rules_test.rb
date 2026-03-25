require "application_system_test_case"

class ImportRulesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    sign_in_as(@user)
  end

  test "create import rule with contains match type" do
    create_rule(pattern: "grocery", match_type: "Contains", account: "Expense Account (expense)")

    assert_text "grocery"
    assert_text "Contains"
    assert_text "Expense Account (expense)"
  end

  test "create import rule with exact match type" do
    create_rule(pattern: "AMAZON PRIME", match_type: "Exact", account: "Expense Account (expense)")

    assert_text "AMAZON PRIME"
    assert_text "Exact"
  end

  test "create import rule with starts_with match type" do
    create_rule(pattern: "PAYPAL", match_type: "Starts with", account: "Revenue Account (revenue)")

    assert_text "PAYPAL"
    assert_text "Starts with"
    assert_text "Revenue Account (revenue)"
  end

  test "create import rule with ends_with match type" do
    create_rule(pattern: "SUBSCRIPTION", match_type: "Ends with", account: "Expense Account (expense)")

    assert_text "SUBSCRIPTION"
    assert_text "Ends with"
  end

  test "edit an import rule" do
    visit import_rules_path
    within("tr", text: "FIXTURE_PATTERN_ONE") do
      click_link "Edit"
    end

    fill_in "Pattern", with: "UPDATED_PATTERN"
    select "Exact", from: "Match Type"
    click_button "Update Import rule"

    assert_text "UPDATED_PATTERN"
    assert_text "Exact"
  end

  test "delete an import rule" do
    visit import_rules_path
    assert_text "FIXTURE_PATTERN_ONE"

    within("tr", text: "FIXTURE_PATTERN_ONE") do
      accept_confirm("Delete this rule?") do
        click_link "Delete"
      end
    end

    assert_no_text "FIXTURE_PATTERN_ONE"
  end

  test "user cannot see another user's import rules" do
    visit import_rules_path
    assert_text "FIXTURE_PATTERN_ONE"

    # Sign in as a different user via a fresh browser session
    Capybara.reset_sessions!
    user_two = users(:two)
    user_two.update!(password: "password123")
    sign_in_as(user_two)

    visit import_rules_path
    assert_no_text "FIXTURE_PATTERN_ONE"
    assert_no_text "FIXTURE_PATTERN_TWO"
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end

  def create_rule(pattern:, match_type:, account:)
    visit import_rules_path
    click_link "New Rule"

    fill_in "Pattern", with: pattern
    select match_type, from: "Match Type"
    select account, from: "Account"
    click_button "Create Import rule"
  end
end
