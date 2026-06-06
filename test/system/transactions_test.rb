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

  test "transaction with several CSV sources shows a single CSV badge" do
    bank = accounts(:asset_account)
    expense = accounts(:expense_account)

    txn = Transaction.create!(
      user: @user, src_account: bank, dest_account: expense,
      currency: currencies(:usd), description: "Overlapping import",
      amount_minor: 8772, transacted_at: 1.day.ago
    )

    2.times do
      csv_import = Csv::Import.new(user: @user, account: bank, state: "imported")
      csv_import.file.attach(
        io: StringIO.new("Date,Description,Amount\n"),
        filename: "statement.csv",
        content_type: "text/csv"
      )
      csv_import.save!
      csv_transaction = Csv::Transaction.create!(
        import: csv_import, row_index: 0,
        transacted_at: 1.day.ago, amount_minor: -8772,
        description: "Overlapping import"
      )
      TransactionSource.create!(ledger_transaction: txn, sourceable: csv_transaction)
    end

    visit transactions_path

    within "##{ActionView::RecordIdentifier.dom_id(txn)}" do
      assert_selector ".source-badge", text: "CSV", count: 1
    end
  end

  test "merged transfer shows aggregated and per-origin source badges" do
    leg_a = Transaction.create!(
      user: @user, src_account: accounts(:asset_account),
      dest_account: accounts(:expense_account), amount_minor: 5000,
      currency: currencies(:usd), description: "Merge leg A", transacted_at: 1.day.ago
    )
    leg_b = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account),
      dest_account: accounts(:linked_asset), amount_minor: 5000,
      currency: currencies(:usd), description: "Merge leg B", transacted_at: 1.day.ago
    )
    sf_txn = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "merge_sf",
      amount: "-50.00", description: "Merge leg A",
      transacted_at: 1.day.ago, posted: 1.day.ago
    )
    lf_txn = Lunchflow::Transaction.create!(
      account: lunchflow_accounts(:unlinked_one), remote_id: "merge_lf",
      amount: "-50.00", currency: "USD", description: "Merge leg B",
      pending: false, date: 1.day.ago.to_date
    )
    TransactionSource.create!(ledger_transaction: leg_a, sourceable: sf_txn)
    TransactionSource.create!(ledger_transaction: leg_b, sourceable: lf_txn)

    merger = Transaction::Merge.new(leg_a, leg_b, user: @user)
    assert merger.call, merger.errors.to_sentence
    result = merger.merged_transaction

    visit transactions_path

    within "##{ActionView::RecordIdentifier.dom_id(result)}" do
      # Aggregated chips in the Date cell, ordered SimpleFIN then Lunch Flow.
      within ".source-badges" do
        assert_selector ".source-badge", text: "SimpleFIN"
        assert_selector ".source-badge", text: "Lunch Flow"
      end

      # Per-origin chips in the collapsible "Merged from:" breakdown.
      click_link "Merged"
      within ".merged-details" do
        assert_selector ".source-badge", text: "SimpleFIN"
        assert_selector ".source-badge", text: "Lunch Flow"
      end
    end

    # The zeroed originals are hidden by the unmerged scope.
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(leg_a)}"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(leg_b)}"
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

  test "selecting transactions reveals the bulk action bar with a count" do
    first = manual_transaction("Bar probe one", 100)
    second = manual_transaction("Bar probe two", 200)

    visit transactions_path
    toggle_select(first)
    toggle_select(second)

    within ".selection-bar" do
      assert_text "2 transactions selected"
    end
  end

  test "restoring a checked selection on reconnect shows the bulk action bar" do
    first = manual_transaction("Reconnect probe one", 100)
    second = manual_transaction("Reconnect probe two", 200)

    visit transactions_path

    # Reproduce a browser reload restoring checkbox state: live-check the boxes without firing a
    # change event, then make Stimulus tear down and reconnect the controller. connect() must
    # re-derive the selection from the already-checked boxes so the bar reappears on its own.
    page.execute_script(<<~JS, first.id, second.id)
      document.querySelector("input.selection-checkbox[data-transaction-id='" + arguments[0] + "']").checked = true
      document.querySelector("input.selection-checkbox[data-transaction-id='" + arguments[1] + "']").checked = true
      window.__selectionWrapper = document.querySelector("[data-controller='transactions--selection']")
      window.__selectionWrapper.removeAttribute("data-controller")
    JS
    page.execute_script("window.__selectionWrapper.setAttribute('data-controller', 'transactions--selection')")

    within ".selection-bar" do
      assert_text "2 transactions selected"
    end
  end

  test "bulk deleting selected transactions removes them from the list" do
    first = manual_transaction("Bulk delete one", 100)
    second = manual_transaction("Bulk delete two", 200)

    visit transactions_path
    toggle_select(first)
    toggle_select(second)
    click_button "Delete"
    click_button "Confirm Delete"

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(first)}"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(second)}"
  end

  test "cancelling the delete confirmation keeps the selection" do
    first = manual_transaction("Keep selection one", 100)
    second = manual_transaction("Keep selection two", 200)

    visit transactions_path
    toggle_select(first)
    toggle_select(second)
    click_button "Delete"
    click_button "Cancel"

    # Selection survives: the bar is back with the same count and Delete works.
    within ".selection-bar" do
      assert_text "2 transactions selected"
    end

    click_button "Delete"
    click_button "Confirm Delete"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(first)}"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(second)}"
  end

  test "exclude stays disabled until every selected transaction is eligible" do
    eligible = sourced_transaction("Eligible row", 100, :transaction_one)
    ineligible = manual_transaction("Manual row", 200)

    visit transactions_path
    toggle_select(eligible)
    toggle_select(ineligible)
    assert_button "Exclude", disabled: true

    toggle_select(ineligible)
    assert_button "Exclude", disabled: false
  end

  test "bulk excluding selected transactions removes them from the default view" do
    first = sourced_transaction("Bulk exclude one", 100, :transaction_one)
    second = sourced_transaction("Bulk exclude two", 200, :transaction_two)

    visit transactions_path
    toggle_select(first)
    toggle_select(second)
    click_button "Exclude"

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(first)}"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(second)}"
  end

  test "bulk restoring selected transactions on the excluded view" do
    first = sourced_transaction("Bulk restore one", 100, :transaction_one)
    second = sourced_transaction("Bulk restore two", 200, :transaction_two)
    Transaction::Exclude.new(first, user: @user).call
    Transaction::Exclude.new(second, user: @user).call

    visit transactions_path(show_excluded: 1)
    toggle_select(first)
    toggle_select(second)
    click_button "Restore"

    within "##{ActionView::RecordIdentifier.dom_id(first)}" do
      assert_no_text "Excluded"
    end
    within "##{ActionView::RecordIdentifier.dom_id(second)}" do
      assert_no_text "Excluded"
    end
  end

  test "combining duplicates keeps the chosen row and moves its sources onto it" do
    sourced = sourced_transaction("Dup sourced", 500, :transaction_one)
    manual = manual_transaction("Dup manual", 500)

    visit transactions_path
    toggle_select(sourced)
    toggle_select(manual)

    assert_button "Combine Duplicates", disabled: false
    assert_button "Merge into Transfer", disabled: true

    click_button "Combine Duplicates"

    within ".selection-confirmation:not([hidden])" do
      find("input[name='combine_survivor'][value='#{manual.id}']").click
      click_button "Combine"
    end

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(sourced)}"
    within "##{ActionView::RecordIdentifier.dom_id(manual)}" do
      assert_selector ".source-badge", text: "SimpleFIN"
    end
  end

  test "a cross-account transfer pair still merges into a transfer" do
    bank_b = accounts(:linked_asset)
    revenue = accounts(:revenue_account)
    withdrawal = manual_transaction("Transfer out", 700)
    deposit = Transaction.create!(
      user: @user, src_account: revenue, dest_account: bank_b,
      amount_minor: 700, currency: currencies(:usd), description: "Transfer in",
      transacted_at: 1.day.ago
    )

    visit transactions_path
    toggle_select(withdrawal)
    toggle_select(deposit)

    assert_button "Merge into Transfer", disabled: false
    assert_button "Combine Duplicates", disabled: true

    click_button "Merge into Transfer"
    within ".selection-confirmation:not([hidden])" do
      click_button "Confirm Merge"
    end

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(withdrawal)}"
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(deposit)}"
  end

  private

  def manual_transaction(description, amount_minor)
    Transaction.create!(
      user: @user,
      src_account: accounts(:asset_account),
      dest_account: accounts(:expense_account),
      amount_minor: amount_minor,
      currency: currencies(:usd),
      description: description,
      transacted_at: 1.day.ago
    )
  end

  def sourced_transaction(description, amount_minor, source_key)
    transaction = manual_transaction(description, amount_minor)
    TransactionSource.create!(ledger_transaction: transaction, sourceable: simplefin_transactions(source_key))
    transaction
  end

  def toggle_select(transaction)
    find("input.selection-checkbox[data-transaction-id='#{transaction.id}']").click
  end

  def sign_in_as(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end
end
