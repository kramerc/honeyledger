require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
  end

  test "logging in shows the signed-in navigation" do
    visit root_path
    assert_link "Login"
    assert_no_link "Logout"

    sign_in_as(@user)

    assert_link "Accounts"
    assert_no_link "Login"
  end

  test "a wrong password shows an alert and stays logged out" do
    visit new_session_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "wrong"
    click_button "Log in"

    assert_text "Try another email or password."
    assert_link "Login"
  end

  test "visiting a protected page redirects to login and back" do
    visit accounts_path
    assert_current_path new_session_path

    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Log in"

    assert_current_path accounts_path
  end

  test "logging out returns to the login page" do
    sign_in_as(@user)

    accept_confirm { click_link "Logout" }

    assert_current_path new_session_path
    assert_link "Login"
    assert_no_link "Logout"
  end

  test "signing up creates an account and signs the user in" do
    visit new_registration_path
    fill_in "Email", with: "new@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_button "Sign up"

    assert_text "Welcome! You have signed up successfully."
    assert_link "Logout"
  end

  test "sign-up validation errors are listed on the form" do
    visit new_registration_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "different1"
    click_button "Sign up"

    within "#error_explanation" do
      assert_text "Email has already been taken"
      assert_text "Password confirmation doesn't match Password"
    end
  end

  test "the login page links to password reset and sign-up" do
    visit new_session_path

    assert_link "Forgot password?"
    assert_link "Sign up"
  end
end
