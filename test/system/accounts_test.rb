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

  test "the sidebar pencil navigates to the account edit page" do
    account = accounts(:asset_account)
    link_id = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"

    visit transactions_path

    find(link_id).hover
    within(link_id) do
      find(".account__edit-pencil").click
    end

    assert_current_path edit_account_path(account)
  end

  test "account detail page lists every linked aggregator source" do
    account = accounts(:linked_asset)
    AccountSource.create!(account: account, sourceable: lunchflow_accounts(:unlinked_one))

    visit account_path(account)

    within('[data-testid="account-sources"]') do
      assert_text "SimpleFIN"
      assert_text "Lunch Flow"
    end
  end

  test "unlinking from the account detail page returns to the account detail page" do
    account = accounts(:linked_asset)
    visit account_path(account)

    within('[data-testid="account-sources"]') do
      accept_confirm do
        click_button "Unlink"
      end
    end

    assert_current_path account_path(account)
    assert_text "SimpleFIN account unlinked successfully."
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

  test "the accounts index groups accounts by kind" do
    visit accounts_path

    # Scope to the page content so the sidebar (which renders the same kind
    # headings) can't make these assertions pass on its own.
    within "main" do
      assert_text "Assets"
      assert_text "Liabilities"
      assert_text "Expenses"
      assert_text "Revenues"
      assert_no_text "Equities" # user one has no equity accounts
    end
  end

  test "account rows show color-coded balances" do
    accounts(:asset_account).update_column(:balance_minor, 12345)
    accounts(:liability_account).update_column(:balance_minor, -5000)

    visit accounts_path

    within row_for(accounts(:asset_account)) do
      assert_selector ".account__balance--positive"
      assert_text "$123.45"
    end
    within row_for(accounts(:liability_account)) do
      assert_selector ".account__balance--negative"
    end
  end

  test "account rows show linked source badges" do
    visit accounts_path

    within row_for(accounts(:linked_asset)) do
      assert_text "SimpleFIN"
    end
    within row_for(accounts(:lunchflow_linked_asset)) do
      assert_text "Lunch Flow"
    end
  end

  test "account rows order source badges like the integrations page (SimpleFIN first)" do
    account = accounts(:linked_asset) # already carries a SimpleFIN source
    AccountSource.create!(account: account, sourceable: lunchflow_accounts(:unlinked_one))

    visit accounts_path

    within row_for(account) do
      labels = all(".source-badge").map(&:text)
      assert_equal [ "SimpleFIN", "Lunch Flow" ], labels
    end
  end

  test "unlinked asset and liability rows offer a Link action" do
    visit accounts_path

    within row_for(accounts(:unlinked_liability)) do
      assert_text "Not linked"
      assert_link "Link", exact: true
    end

    within row_for(accounts(:linked_asset)) do
      assert_no_link "Link", exact: true # account name "Linked Asset" contains "Link"
    end
  end

  test "expense and revenue groups drop the Sources column, since they can't be linked" do
    visit accounts_path

    within row_for(accounts(:expense_account)) do
      assert_no_text "Not linked"
      assert_no_link "Link", exact: true
      assert_no_selector ".source-badge"
    end

    # The column header is gone for these groups but stays for linkable ones.
    within find("section.accounts-group", text: "Expenses") do
      within(".row.header") { assert_no_text "Sources" }
    end
    within find("section.accounts-group", text: "Assets") do
      within(".row.header") { assert_text "Sources" }
    end
  end

  test "clicking an account name opens its detail page" do
    account = accounts(:unlinked_liability)
    visit accounts_path

    within row_for(account) do
      click_link account.name
    end

    assert_current_path account_path(account)
  end

  test "the Transactions action opens the account's transactions" do
    account = accounts(:unlinked_liability)
    visit accounts_path

    within row_for(account) do
      click_link "Transactions"
    end

    assert_current_path account_transactions_path(account)
  end

  test "the Edit action opens the account edit form" do
    account = accounts(:unlinked_liability)
    visit accounts_path

    within row_for(account) do
      click_link "Edit"
    end

    assert_current_path edit_account_path(account)
  end

  test "Delete is hidden for accounts that still have transactions" do
    visit accounts_path

    within row_for(accounts(:asset_account)) do
      assert_no_button "Delete"
    end
  end

  test "deleting an account with no transactions removes it from the index and sidebar" do
    account = Account.create!(user: @user, currency: currencies(:usd), name: "Index Delete Probe", kind: :asset)
    visit accounts_path

    row = row_for(account)
    sidebar_item = "##{ActionView::RecordIdentifier.dom_id(account, :sidebar_item)}"
    assert_selector row

    within(row) do
      accept_confirm do
        click_button "Delete"
      end
    end

    assert_text "Account was successfully destroyed."
    assert_no_selector row
    assert_no_selector sidebar_item
  end

  test "shows a friendly empty state when there are no accounts" do
    empty_user = User.create!(email: "empty@example.com", password: "password123")

    accept_confirm { click_link "Logout" }
    assert_no_link "Logout"

    sign_in_as(empty_user)
    visit accounts_path

    assert_text "No accounts yet"
    assert_link "New account"
    assert_link "Go to Integrations"
  end

  test "merging two expense accounts folds one into the kept account" do
    keeper = accounts(:expense_account) # has fixture transaction one ($50.00)
    keeper.reset_balance
    duplicate = Account.create!(user: @user, name: "Duplicate Expense", kind: :expense, currency: currencies(:usd))
    Transaction.create!(
      user: @user, src_account: accounts(:asset_account), dest_account: duplicate,
      amount_minor: 2500, currency: currencies(:usd), transacted_at: 1.day.ago
    )

    visit accounts_path

    toggle_select(keeper)
    toggle_select(duplicate)

    within ".selection-bar" do
      assert_text "2 accounts selected"
      click_button "Merge"
    end

    find("input[name='target_account_id'][value='#{keeper.id}']").click
    click_button "Confirm merge"

    assert_text "Accounts merged into Expense Account."
    assert_no_selector row_for(duplicate)
    within row_for(keeper) do
      assert_text "$75.00" # $50.00 (fixture) + $25.00 (moved)
    end
  end

  test "the merge confirmation shows each account's transaction count" do
    keeper = accounts(:expense_account) # has fixture transaction one => 1 transaction
    duplicate = Account.create!(user: @user, name: "Duplicate Expense", kind: :expense, currency: currencies(:usd))
    2.times do |index|
      Transaction.create!(
        user: @user, src_account: accounts(:asset_account), dest_account: duplicate,
        amount_minor: 100 * (index + 1), currency: currencies(:usd), transacted_at: 1.day.ago
      )
    end

    visit accounts_path
    toggle_select(keeper)
    toggle_select(duplicate)
    within(".selection-bar") { click_button "Merge" }

    within ".selection-confirmation" do
      assert_text "Expense Account"
      assert_text "1 transaction"
      assert_text "Duplicate Expense"
      assert_text "2 transactions"
    end
  end

  test "restoring a checked selection on reconnect shows the merge bar" do
    keeper = accounts(:expense_account)
    duplicate = Account.create!(user: @user, name: "Duplicate Expense", kind: :expense, currency: currencies(:usd))

    visit accounts_path

    # Reproduce a browser reload restoring checkbox state: live-check the boxes without firing a
    # change event, then make Stimulus tear down and reconnect the controller. connect() must
    # re-derive the selection from the already-checked boxes so the bar reappears on its own.
    page.execute_script(<<~JS, keeper.id, duplicate.id)
      document.querySelector("input.selection-checkbox[data-account-id='" + arguments[0] + "']").checked = true
      document.querySelector("input.selection-checkbox[data-account-id='" + arguments[1] + "']").checked = true
      window.__mergeWrapper = document.querySelector("[data-controller='accounts--selection']")
      window.__mergeWrapper.removeAttribute("data-controller")
    JS
    page.execute_script("window.__mergeWrapper.setAttribute('data-controller', 'accounts--selection')")

    within ".selection-bar" do
      assert_text "2 accounts selected"
    end
  end

  private

  def row_for(account)
    "##{ActionView::RecordIdentifier.dom_id(account)}"
  end

  def toggle_select(account)
    find("input.selection-checkbox[data-account-id='#{account.id}']").click
  end

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end
end
