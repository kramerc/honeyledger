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

    within("##{ActionView::RecordIdentifier.dom_id(src, :sidebar_link)}") do
      assert_text "-$12.34"
    end
    within("##{ActionView::RecordIdentifier.dom_id(dest, :sidebar_link)}") do
      assert_text "$12.34"
    end
  end

  test "transaction with multiple sources shows a badge per aggregator" do
    bank = accounts(:linked_asset)
    expense = accounts(:expense_account)
    AccountSource.create!(account: bank, sourceable: lunchflow_accounts(:unlinked_one))

    txn = Transaction.create!(
      user: @user, src_account: bank, dest_account: expense,
      currency: currencies(:usd), description: "Multi-sourced txn",
      amount_minor: 1234, transacted_at: 1.day.ago
    )
    sf_txn = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one),
      remote_id: "ui_multi_sf",
      amount: "-12.34",
      description: "Multi-sourced txn",
      transacted_at: 1.day.ago,
      posted: 1.day.ago
    )
    lf_txn = Lunchflow::Transaction.create!(
      account: lunchflow_accounts(:unlinked_one),
      remote_id: "ui_multi_lf",
      amount: "-12.34",
      currency: "USD",
      description: "Multi-sourced txn",
      pending: false,
      date: 1.day.ago.to_date
    )
    TransactionSource.create!(ledger_transaction: txn, sourceable: sf_txn)
    TransactionSource.create!(ledger_transaction: txn, sourceable: lf_txn)

    visit transactions_path

    within "##{ActionView::RecordIdentifier.dom_id(txn)}" do
      assert_selector ".source-badge", text: "SimpleFIN"
      assert_selector ".source-badge", text: "Lunch Flow"
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

  private

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end
end
