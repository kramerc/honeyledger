require "application_system_test_case"

class TransactionsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    sign_in_as(@user)
  end

  test "sidebar balance updates live when a transaction is created" do
    src = accounts(:asset_account)
    dest = accounts(:expense_account)
    src.update!(balance_minor: 0)
    dest.update!(balance_minor: 0)

    visit transactions_path

    fill_in "transaction[description]", with: "Live update probe"
    select src.name, from: "transaction[src_account_id]"
    select dest.name, from: "transaction[dest_account_id]"
    fill_in "transaction[amount]", with: "12.34"
    click_button "Create"

    within("##{ActionView::RecordIdentifier.dom_id(src, :sidebar_balance)}") do
      assert_text "-$12.34"
    end
    within("##{ActionView::RecordIdentifier.dom_id(dest, :sidebar_balance)}") do
      assert_text "$12.34"
    end
  end

  test "sidebar active state survives a live update" do
    account = accounts(:asset_account)
    other = accounts(:expense_account)
    account.update!(balance_minor: 0)
    other.update!(balance_minor: 0)

    visit account_path(account)

    balance_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_balance)}"
    active_link_selector = "a.active[href='#{account_transactions_path(account)}']"
    assert_selector active_link_selector

    Transaction.create!(
      user: @user,
      src_account: account,
      dest_account: other,
      description: "Side effect",
      amount_minor: 500,
      currency: currencies(:usd),
      transacted_at: Time.current
    )

    within(balance_id) do
      assert_text "-$5.00"
    end
    assert_selector active_link_selector
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
