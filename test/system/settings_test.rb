require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "settings is reachable from the navigation" do
    click_link "Settings"

    assert_current_path settings_path
    assert_text "Passkeys"
  end

  test "lists each passkey with when it was added and last used" do
    visit settings_path

    within "#passkey_#{passkeys(:laptop).id}" do
      assert_text "Laptop"
      assert_text passkeys(:laptop).created_at.strftime("%B %d, %Y")
      assert_text "Never"
      assert_button "Delete"
    end
    assert_no_text "Phone"
  end

  test "shows an empty state when there are no passkeys" do
    passkeys(:laptop).destroy!

    visit settings_path

    assert_text "No passkeys yet."
  end

  test "deleting a passkey removes it from the list" do
    visit settings_path

    within "#passkey_#{passkeys(:laptop).id}" do
      accept_confirm { click_button "Delete" }
    end

    assert_text "Passkey removed."
    assert_no_text "Laptop"
    assert_text "No passkeys yet."
  end

  test "a fresh login can add a passkey right away" do
    visit settings_path

    assert_button "Add passkey"
    assert_no_link "Confirm your password to add a passkey"
  end

  test "an older session confirms the password before adding a passkey" do
    @user.sessions.update_all(created_at: 1.hour.ago)

    visit settings_path
    assert_no_button "Add passkey"
    click_link "Confirm your password to add a passkey"

    fill_in "Password", with: "password123"
    click_button "Confirm password"

    assert_text "Password confirmed."
    assert_button "Add passkey"
  end

  test "a wrong password during confirmation is reported" do
    @user.sessions.update_all(created_at: 1.hour.ago)

    visit new_reauthentication_path
    fill_in "Password", with: "wrong"
    click_button "Confirm password"

    assert_text "That password is not right."
    assert_current_path new_reauthentication_path
  end

  test "the login page offers passkey sign-in" do
    accept_confirm { click_link "Logout" }

    assert_current_path new_session_path
    assert_button "Sign in with a passkey"
  end
end
