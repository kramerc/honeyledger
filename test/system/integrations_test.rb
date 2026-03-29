require "application_system_test_case"

class IntegrationsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    sign_in_as(@user)
  end

  test "displays both connections with status" do
    visit integrations_path

    assert_text "SimpleFIN"
    assert_text "Lunch Flow"
    assert_text "Connected since"
    assert_button "Refresh", count: 2
    assert_button "Disconnect", count: 2
  end

  test "displays connect buttons when not connected" do
    @user.simplefin_connection.destroy!
    @user.lunchflow_connection.destroy!

    visit integrations_path

    assert_text "Not connected", count: 2
    assert_button "Connect", count: 2
  end

  test "displays SimpleFIN accounts with link controls" do
    visit integrations_path

    assert_text "SimpleFIN Accounts"
    # Fixture accounts
    assert_text "Test Checking"
    assert_text "Test Savings"
    # Linked account shows unlink button
    assert_button "Unlink"
    # Unlinked accounts show link button
    assert_button "Link"
    # Import link for unlinked accounts
    assert_link "Import"
  end

  test "displays Lunch Flow accounts with status" do
    visit integrations_path

    assert_text "Lunch Flow Accounts"
    assert_text "Test Bank Checking"
    assert_text "ACTIVE"
  end

  test "displays Lunch Flow ERROR status with action link" do
    lf_account = lunchflow_accounts(:unlinked_one)
    lf_account.update!(status: "ERROR")

    visit integrations_path

    assert_text "ERROR - resolve on"
    assert_link "Lunch Flow", href: "https://lunchflow.app"
  end

  test "displays Lunch Flow DISCONNECTED status with action link" do
    lf_account = lunchflow_accounts(:unlinked_one)
    lf_account.update!(status: "DISCONNECTED")

    visit integrations_path

    assert_text "DISCONNECTED - reconnect on"
    assert_link "Lunch Flow", href: "https://lunchflow.app"
  end

  test "displays Lunch Flow connection error" do
    @user.lunchflow_connection.update!(error: "Active subscription required.")

    visit integrations_path

    assert_text "Active subscription required."
  end

  test "displays SimpleFIN errlist" do
    @user.simplefin_connection.update!(errlist: [ { "code" => "auth_failed", "msg" => "Login credentials expired" } ])

    visit integrations_path

    assert_text "auth_failed"
    assert_text "Login credentials expired"
    assert_link "My Account on SimpleFIN"
  end

  test "import link pre-fills new account form from Lunch Flow" do
    lf_account = lunchflow_accounts(:unlinked_one)

    visit integrations_path

    # Find the Import link in the Lunch Flow unlinked account row
    within("tr", text: lf_account.name) do
      click_link "Import"
    end

    assert_field "Name", with: lf_account.name
  end

  test "linking a Lunch Flow account shows success" do
    lf_account = lunchflow_accounts(:unlinked_one)

    visit integrations_path

    within("tr", text: lf_account.name) do
      select "Unlinked Liability", from: "Account to link"
      click_button "Link"
    end

    assert_text "Lunch Flow account linked successfully."
  end

  test "unlinking a Lunch Flow account shows success" do
    lf_account = lunchflow_accounts(:linked_one)

    visit integrations_path

    within("tr", text: lf_account.name) do
      accept_confirm do
        click_button "Unlink"
      end
    end

    assert_text "Lunch Flow account unlinked successfully."
  end

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end
end
