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
