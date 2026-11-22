require "application_system_test_case"

class IntegrationsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "displays both connections with status" do
    visit integrations_path

    assert_text "SimpleFIN"
    assert_text "Lunch Flow"
    assert_text "Connected since"
    assert_button "Refresh", count: 3 # two aggregators plus the fixture wallet
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

  test "shows the balance SimpleFIN reported for each account" do
    visit integrations_path

    within find("table", text: "Organization") do
      assert_selector "th", text: "Balance"
      assert_selector "th", text: "Balance As Of"
      within("tr", text: "Test Savings") do
        assert_text "$5,000.00"
        assert_text "January 13, 2026 05:53 AM"
      end
    end
  end

  test "shows the balance Lunch Flow reported for each account" do
    visit integrations_path

    within find("table", text: "Institution") do
      assert_selector "th", text: "Balance"
      assert_selector "th", text: "Balance As Of"
      within("tr", text: "Test Bank Savings") do
        assert_text "$10,000.00"
        # When the balance last changed, not when the account was last seen.
        assert_text "April 20, 2026 09:30 AM"
        assert_no_text "April 25, 2026"
      end
    end
  end

  test "shows the currency SimpleFIN reported for each account" do
    simplefin_accounts(:unlinked_one).update!(currency: "")

    visit integrations_path

    within find("table", text: "Organization") do
      assert_selector "th", text: "Currency"
      assert_selector "td", exact_text: "USD"
      within("tr", text: "Test Savings") do
        assert_text "(missing)"
        assert_no_text "$"
      end
    end
  end

  test "shows the currency Lunch Flow reported for each account" do
    visit integrations_path

    within find("table", text: "Institution") do
      assert_selector "th", text: "Currency"
      within("tr", text: "Test Bank Savings") { assert_text "USD" }
    end
  end

  test "sorts SimpleFIN accounts by institution then account name" do
    # Insertion order (linked, unlinked, reconciled) deliberately differs from the
    # expected sorted order, and account names alone sort differently than the
    # institution-first order, so this also proves institution is the primary key.
    simplefin_accounts(:linked_one).update!(org: { "name" => "Summit Bank" }, name: "Alpha Account")
    simplefin_accounts(:unlinked_one).update!(org: { "name" => "Summit Bank" }, name: "Beta Account")
    simplefin_accounts(:reconciled_one).update!(org: { "name" => "Harbor Bank" }, name: "Zulu Account")

    visit integrations_path

    within find("table", text: "Organization") do
      account_names = all("tr td:nth-child(2)").map { |cell| cell.text.strip }
      assert_equal [ "Zulu Account", "Alpha Account", "Beta Account" ], account_names
    end
  end

  test "sorts Lunch Flow accounts by institution then account name" do
    lunchflow_accounts(:linked_one).update!(institution_name: "Aspen Bank", name: "Yankee Account")
    lunchflow_accounts(:unlinked_one).update!(institution_name: "Zephyr Bank", name: "Alpha Account")

    visit integrations_path

    within find("table", text: "Institution") do
      account_names = all("tr td:nth-child(2)").map { |cell| cell.text.strip }
      assert_equal [ "Yankee Account", "Alpha Account" ], account_names
    end
  end

  test "SimpleFIN link form groups linkable accounts by kind" do
    sf_account = simplefin_accounts(:unlinked_one)

    visit integrations_path

    within("tr", text: sf_account.name) do
      within("select[name='simplefin_account[ledger_account_id]']") do
        assert_selector "optgroup[label='Asset']", visible: :all
        assert_selector "optgroup[label='Liability']", visible: :all
      end
    end
  end

  test "displays Lunch Flow accounts with status" do
    visit integrations_path

    assert_text "Lunch Flow Accounts"
    assert_text "Test Bank Checking"
    assert_text "ACTIVE"
  end

  test "Lunch Flow link form groups linkable accounts by kind" do
    lf_account = lunchflow_accounts(:unlinked_one)

    visit integrations_path

    within("tr", text: lf_account.name) do
      within("select[name='lunchflow_account[ledger_account_id]']") do
        assert_selector "optgroup[label='Asset']", visible: :all
        assert_selector "optgroup[label='Liability']", visible: :all
      end
    end
  end

  test "displays Lunch Flow ERROR status with action link" do
    lf_account = lunchflow_accounts(:unlinked_one)
    lf_account.update!(status: "ERROR")

    visit integrations_path

    assert_selector "span.text-error", text: "ERROR - resolve on"
    assert_link "Lunch Flow", href: "https://lunchflow.app"
  end

  test "displays Lunch Flow DISCONNECTED status with action link" do
    lf_account = lunchflow_accounts(:unlinked_one)
    lf_account.update!(status: "DISCONNECTED")

    visit integrations_path

    assert_selector "span.text-error", text: "DISCONNECTED - reconnect on"
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

  test "linking a second integration to a ledger account that already has one succeeds" do
    lf_account = lunchflow_accounts(:unlinked_one)
    multi_sourced = accounts(:linked_asset) # already has SimpleFIN source via fixtures

    visit integrations_path

    within("tr", text: lf_account.name) do
      select multi_sourced.name, from: "Account to link"
      click_button "Link"
    end

    assert_text "Lunch Flow account linked successfully."
    assert_includes lf_account.reload.ledger_accounts, multi_sourced
  end

  test "hides stale unlinked aggregator accounts" do
    @user.simplefin_connection.update!(refreshed_at: Time.current)
    stale_simplefin = simplefin_accounts(:unlinked_one)
    stale_simplefin.update!(last_seen_at: 1.day.ago)

    @user.lunchflow_connection.update!(refreshed_at: Time.current)
    stale_lunchflow = lunchflow_accounts(:unlinked_one)
    stale_lunchflow.update!(last_seen_at: 1.day.ago)

    visit integrations_path

    assert_no_text stale_simplefin.name
    assert_no_text stale_lunchflow.name
  end

  test "shows stale linked aggregator accounts with stale indicator" do
    @user.simplefin_connection.update!(refreshed_at: Time.current)
    stale_linked_simplefin = simplefin_accounts(:linked_one)
    stale_linked_simplefin.update!(last_seen_at: 1.day.ago)

    @user.lunchflow_connection.update!(refreshed_at: Time.current)
    stale_linked_lunchflow = lunchflow_accounts(:linked_one)
    stale_linked_lunchflow.update!(last_seen_at: 1.day.ago)

    visit integrations_path

    within("tr", text: stale_linked_simplefin.name) do
      assert_selector "span.marker", text: "(stale)"
    end

    within("tr", text: stale_linked_lunchflow.name) do
      assert_selector "span.marker", text: "(stale)"
    end
  end

  test "does not show stale indicator on current aggregator accounts" do
    visit integrations_path

    assert_no_text "(stale)"
  end

  test "adds a Bitcoin wallet by address" do
    visit integrations_path
    click_button "Add wallet"

    fill_in "Label", with: "Spending wallet"
    fill_in "Address or extended public key", with: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
    # The refresh would query a public explorer; the job itself is covered elsewhere.
    Blockchain::Connection.stub_any_instance(:refresh, nil) do
      click_button "Add wallet"
      assert_text "Wallet added"
    end

    assert_text "Spending wallet"
    assert_text "bc1qw508d6…v8f3t4"
  end

  test "shows a validation error for a private key" do
    visit new_blockchain_connection_path

    fill_in "Address or extended public key", with: "zprvAdG4iTXWBoARxkkzNpNh8r6Qag3irQB8PzEMkAFeTRXxHpbF9z4QgEvBRmfvqWvGp42t42nvgGpNgYSJA9iefm1yYNZKEm7z6qUWCroSQnE"
    click_button "Add wallet"

    assert_text "Only paste the public key"
  end

  test "lists wallet accounts and links one to a ledger account" do
    ledger_account = @user.accounts.create!(name: "Hardware wallet", kind: :asset, currency: currencies(:btc))

    visit integrations_path

    assert_text "Wallet Accounts"
    within("tr", text: "Cold storage", match: :first) do
      assert_button "Refresh"
      assert_button "Remove"
    end

    row = find("select[name='blockchain_account[ledger_account_id]']").ancestor("tr")
    within(row) do
      assert_text "Bitcoin"
      assert_text "BTC"
      select "Hardware wallet", from: "blockchain_account[ledger_account_id]"
      click_button "Link"
    end

    assert_text "Wallet account linked successfully."
    visit account_path(ledger_account)
    assert_text "On-chain: Bitcoin"
  end

  test "shows a wallet refresh error in its connection row" do
    blockchain_connections(:xpub_wallet).update!(error: "Rate limited by the explorer")

    visit integrations_path

    within("tr", text: "Cold storage", match: :first) do
      assert_text "Rate limited by the explorer"
    end
  end
end
