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
    select src.name, from: "transaction[anchor_account_id]"
    select dest.name, from: "transaction[counterparty_account_id]"
    fill_in "transaction[amount]", with: "-12.34"
    click_button "Create"

    within("##{ActionView::RecordIdentifier.dom_id(src, :sidebar_link)}") do
      assert_text "-$12.34"
    end
    within("##{ActionView::RecordIdentifier.dom_id(dest, :sidebar_link)}") do
      assert_text "$12.34"
    end
  end

  test "sidebar active state survives a live update" do
    account = accounts(:asset_account)
    other = accounts(:expense_account)
    account.update!(balance_minor: 0)
    other.update!(balance_minor: 0)

    visit account_path(account)

    balance_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"
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

  test "unfiltered transactions index renders Account + Counterparty headers" do
    visit transactions_path

    within(".transactions .row.header") do
      assert_text "Account"
      assert_text "Counterparty"
      assert_no_text "From"
      assert_no_text "To"
    end
  end

  test "account-scoped transactions index hides the Account header" do
    visit account_transactions_path(accounts(:asset_account))

    within(".transactions .row.header") do
      assert_text "Counterparty"
      assert_no_text "From"
      assert_no_text "To"
      assert_no_selector "div", exact_text: "Account"
    end
  end

  test "row shows signed amount with outflow class when scoped to src account" do
    asset = accounts(:asset_account)
    Transaction.create!(
      user: @user,
      src_account: asset,
      dest_account: accounts(:expense_account),
      amount_minor: 4250,
      currency: currencies(:usd),
      description: "Coffee shop",
      transacted_at: Time.current
    )

    visit account_transactions_path(asset)

    assert_selector ".tx-amount--outflow", text: "-$42.50"
  end

  test "row shows signed amount with inflow class when scoped to dest account" do
    asset = accounts(:asset_account)
    Transaction.create!(
      user: @user,
      src_account: accounts(:revenue_account),
      dest_account: asset,
      amount_minor: 100000,
      currency: currencies(:usd),
      description: "Paycheck inflow probe",
      transacted_at: Time.current
    )

    visit account_transactions_path(asset)

    assert_selector ".tx-amount--inflow", text: "$1,000.00"
  end

  test "creating a transaction with a negative amount infers outflow" do
    asset = accounts(:asset_account)
    expense = accounts(:expense_account)
    asset.update!(balance_minor: 0)

    visit account_transactions_path(asset)

    fill_in "transaction[description]", with: "Scoped outflow"
    select expense.name, from: "transaction[counterparty_account_id]"
    fill_in "transaction[amount]", with: "-5.00"
    click_button "Create"

    assert_text "Scoped outflow"

    created = Transaction.find_by(description: "Scoped outflow")
    assert_not_nil created
    assert_equal asset.id, created.src_account_id
    assert_equal expense.id, created.dest_account_id
    assert_equal 500, created.amount_minor
  end

  test "creating a transaction with a positive amount infers inflow" do
    asset = accounts(:asset_account)
    revenue = accounts(:revenue_account)
    asset.update!(balance_minor: 0)

    visit account_transactions_path(asset)

    fill_in "transaction[description]", with: "Scoped inflow"
    select revenue.name, from: "transaction[counterparty_account_id]"
    fill_in "transaction[amount]", with: "200.00"
    click_button "Create"

    assert_text "Scoped inflow"

    created = Transaction.find_by(description: "Scoped inflow")
    assert_not_nil created
    assert_equal revenue.id, created.src_account_id
    assert_equal asset.id, created.dest_account_id
    assert_equal 20000, created.amount_minor
  end

  test "creating a transaction on the unfiltered view requires picking an anchor" do
    asset = accounts(:asset_account)
    expense = accounts(:expense_account)

    visit transactions_path

    fill_in "transaction[description]", with: "Unfiltered create"
    select asset.name, from: "transaction[anchor_account_id]"
    select expense.name, from: "transaction[counterparty_account_id]"
    fill_in "transaction[amount]", with: "-7.50"
    click_button "Create"

    assert_text "Unfiltered create"

    created = Transaction.find_by(description: "Unfiltered create")
    assert_not_nil created
    assert_equal asset.id, created.src_account_id
    assert_equal expense.id, created.dest_account_id
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
