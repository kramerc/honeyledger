require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  test "signed out, the home page offers login and sign-up" do
    visit root_path

    assert_link "Login"
    assert_link "Sign up"
    assert_no_text "Needs attention"
  end

  test "shows what needs attention, net worth, and recent transactions" do
    user = users(:one)
    user.lunchflow_connection.update!(error: "Invalid API key", refreshed_at: 1.hour.ago)
    Transaction.create!(user: user, src_account: accounts(:asset_account), dest_account: accounts(:expense_account),
      description: "Sample Vendor purchase", amount_minor: 1_250, currency: currencies(:usd), transacted_at: Time.current)
    # After the transaction, whose callback would otherwise move the balance.
    accounts(:asset_account).update_column(:balance_minor, 123_456)
    accounts(:liability_account).update_column(:balance_minor, -23_456)

    sign_in_as(user)

    assert_current_path dashboard_path
    within("section", text: "Needs attention") do
      assert_selector ".dashboard__attention-item--error", text: "Lunch Flow: Invalid API key"
      click_link "Lunch Flow: Invalid API key"
    end
    assert_current_path integrations_path

    visit dashboard_path
    within(".dashboard__net-worth") do
      within("tr", text: "USD") do
        assert_text "$1,234.56"
        assert_text "-$234.56"
        assert_selector ".dashboard__net--positive", text: "$1,000.00"
      end
    end
    within(".dashboard__recent") do
      within("tr", text: "Sample Vendor purchase") do
        assert_text "Asset Account → Expense Account"
        assert_text "$12.50"
      end
    end
    assert_link "View all transactions", href: transactions_path
  end

  test "a user with nothing to fix sees that everything is in sync" do
    user = User.create!(email: "clean@example.com", password: "password123")
    user.accounts.create!(name: "Checking", kind: :asset, currency: currencies(:usd))

    sign_in_as(user)

    assert_text "Everything's in sync."
    assert_no_text "Get started"
  end

  test "a new user is offered first steps" do
    sign_in_as(User.create!(email: "new@example.com", password: "password123"))

    within(".empty-state") do
      assert_text "Get started"
      assert_link "New account"
      assert_link "Go to Integrations"
    end
    assert_no_selector ".dashboard__net-worth"
  end

  test "on a phone the net worth table shows only the net, without scrolling" do
    user = users(:one)
    user.accounts.create!(name: "Coins", kind: :asset, currency: currencies(:btc)).update_column(:balance_minor, 289_912_845)
    accounts(:liability_account).update_column(:balance_minor, -37_257_344)
    sign_in_as(user)
    page.driver.browser.manage.window.resize_to(390, 900)

    within(".dashboard__net-worth") do
      assert_text "BTC"
      assert_no_text "Liabilities"
    end
    assert_not page.evaluate_script("document.querySelector('.dashboard__net-worth').parentElement.scrollWidth > document.querySelector('.dashboard__net-worth').parentElement.clientWidth")
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end
end
