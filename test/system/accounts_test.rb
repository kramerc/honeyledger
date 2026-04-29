require "application_system_test_case"

class AccountsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    sign_in_as(@user)
  end

  test "renaming an account updates the sidebar live and preserves the active class" do
    account = accounts(:asset_account)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"
    active_link_selector = "a.active[href='#{account_transactions_path(account)}']"

    visit account_path(account)
    assert_selector active_link_selector

    Account.find(account.id).update!(name: "Freshly Renamed")

    within(link_id) do
      assert_text "Freshly Renamed"
    end
    assert_selector active_link_selector
  end

  test "creating a new account makes it appear in the sidebar live" do
    visit transactions_path

    new_account = Account.create!(
      user: @user,
      currency: currencies(:usd),
      name: "Live Insert Probe",
      kind: :liability
    )

    within("#sidebar_accounts_liability") do
      assert_selector "##{ActionView::RecordIdentifier.dom_id(new_account, :sidebar_item)}"
      assert_text "Live Insert Probe"
    end
  end

  test "user can inline-rename an account from the sidebar" do
    account = accounts(:asset_account)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path
    assert_selector link_id

    find(link_id).hover
    within(link_id) do
      find(".account__rename-pencil", visible: :all).click
      input = find(".account__rename-input")
      input.set("Renamed Inline")
      input.send_keys(:return)
    end

    within(link_id) do
      assert_text "Renamed Inline"
    end
    assert_equal "Renamed Inline", account.reload.name
  end

  test "escape cancels the inline rename and restores the original name" do
    account = accounts(:asset_account)
    original = account.name
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path

    find(link_id).hover
    within(link_id) do
      find(".account__rename-pencil", visible: :all).click
      input = find(".account__rename-input")
      input.set("Should Not Save")
      input.send_keys(:escape)
      assert_text original
      assert_no_selector ".account__rename-input:not([hidden])"
    end
    assert_equal original, account.reload.name
  end

  test "invalid inline rename shows an error and preserves edit state" do
    account = accounts(:asset_account)
    Account.create!(user: @user, currency: account.currency, name: "Conflict Name", kind: account.kind)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path

    find(link_id).hover
    within(link_id) do
      find(".account__rename-pencil", visible: :all).click
      input = find(".account__rename-input")
      input.set("Conflict Name")
      input.send_keys(:return)
      assert_selector ".account__rename-error", text: /taken/i
      assert_equal "Conflict Name", find(".account__rename-input").value
    end
    assert_not_equal "Conflict Name", account.reload.name
  end

  test "fixing an invalid inline rename clears the error and saves" do
    account = accounts(:asset_account)
    Account.create!(user: @user, currency: account.currency, name: "Conflict Name", kind: account.kind)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path

    find(link_id).hover
    within(link_id) do
      find(".account__rename-pencil", visible: :all).click
      input = find(".account__rename-input")
      input.set("Conflict Name")
      input.send_keys(:return)
      assert_selector ".account__rename-error"

      find(".account__rename-input").set("Fresh Valid Name")
      begin
        find(".account__rename-input").send_keys(:return)
      rescue Selenium::WebDriver::Error::StaleElementReferenceError
        # Enter was sent successfully; element became stale because the success
        # response triggered an immediate re-render. Action took effect.
      end

      assert_no_selector ".account__rename-error"
      assert_text "Fresh Valid Name"
    end
    assert_equal "Fresh Valid Name", account.reload.name
  end

  test "clicking inside the rename input does not navigate" do
    account = accounts(:asset_account)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path
    starting_path = current_path

    find(link_id).hover
    within(link_id) do
      find(".account__rename-pencil", visible: :all).click
      find(".account__rename-input").click
      assert_no_selector ".account__rename-input[hidden]"
    end
    assert_equal starting_path, current_path
  end

  test "destroying an account removes it from the sidebar live" do
    account = Account.create!(
      user: @user,
      currency: currencies(:usd),
      name: "Live Delete Probe",
      kind: :asset
    )
    visit transactions_path
    assert_selector "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_item)}"

    account.destroy!

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_item)}"
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
