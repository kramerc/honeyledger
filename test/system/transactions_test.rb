require "application_system_test_case"

class TransactionsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
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
    # Expense accounts are not listed in the sidebar.
    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(dest, :sidebar_link)}"
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

  test "creating a transaction on an account-filtered index inserts the row in place" do
    account = accounts(:asset_account)
    # Newer than every row in the account's list, but on neither of its sides.
    # It is the row the unscoped anchor query used to pick, and it is not on the
    # page, so the insertion used to be dropped silently.
    Transaction.create!(
      user: @user, src_account: accounts(:liability_account), dest_account: accounts(:expense_account),
      amount_minor: 100, currency: currencies(:usd), description: "Off-list row",
      transacted_at: 1.day.ago
    )

    visit account_transactions_path(account)
    assert_selector "#transactions .transaction", count: 2
    assert_no_text "Off-list row"

    fill_in "transaction[description]", with: "Filtered live create"
    select account.name, from: "transaction[src_account_id]"
    select accounts(:expense_account).name, from: "transaction[dest_account_id]"
    fill_in "transaction[amount]", with: "31.00"
    click_button "Create"

    assert_text "Filtered live create"
    assert_selector "#transactions .transaction", count: 3
    created = Transaction.find_by!(description: "Filtered live create")
    assert_equal ActionView::RecordIdentifier.dom_id(created),
                 first("#transactions > turbo-frame")[:id],
                 "the newest transaction should be inserted at the top of the list"
  end

  test "creating a transaction on the unfiltered index inserts the row in place" do
    visit transactions_path
    assert_selector "#transactions .transaction", count: 2

    fill_in "transaction[description]", with: "Unfiltered live create"
    select accounts(:asset_account).name, from: "transaction[src_account_id]"
    select accounts(:expense_account).name, from: "transaction[dest_account_id]"
    fill_in "transaction[amount]", with: "31.00"
    click_button "Create"

    assert_text "Unfiltered live create"
    assert_selector "#transactions .transaction", count: 3
    created = Transaction.find_by!(description: "Unfiltered live create")
    assert_equal ActionView::RecordIdentifier.dom_id(created),
                 first("#transactions > turbo-frame")[:id],
                 "the newest transaction should be inserted at the top of the list"
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

  test "combining a one-sided duplicate into a merged transfer keeps the transfer" do
    duplicate = sourced_transaction("Pending charge", 900, :transaction_two)
    transfer = merged_transfer(900)

    visit transactions_path
    toggle_select(duplicate)
    toggle_select(transfer)

    assert_button "Combine Duplicates", disabled: false
    assert_button "Merge into Transfer", disabled: true

    click_button "Combine Duplicates"

    within ".selection-confirmation:not([hidden])" do
      assert_checked_field "combine_survivor", with: transfer.id.to_s, visible: :all
      assert_field "combine_survivor", with: duplicate.id.to_s, disabled: true, visible: :all
      within ".selection-confirmation__option--disabled" do
        assert_text "Will be removed"
      end
      click_button "Combine"
    end

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(duplicate)}"
    within "##{ActionView::RecordIdentifier.dom_id(transfer)}" do
      assert_selector ".source-badge", text: "SimpleFIN"
    end
  end

  test "combine stays disabled when the transfer is on a different bank account" do
    duplicate = manual_transaction("Elsewhere charge", 900)
    transfer = Transaction.create!(
      user: @user, src_account: accounts(:lunchflow_linked_asset), dest_account: accounts(:linked_asset),
      amount_minor: 900, currency: currencies(:usd), description: "Other transfer",
      transacted_at: 1.day.ago
    )

    visit transactions_path
    toggle_select(duplicate)
    toggle_select(transfer)

    assert_button "Combine Duplicates", disabled: true
  end

  test "combine stays disabled when a one-sided row is an edited merge result" do
    duplicate = manual_transaction("Plain charge", 900)
    edited = merged_transfer(900)
    edited.update!(dest_account: accounts(:expense_account))

    visit transactions_path
    toggle_select(duplicate)
    toggle_select(edited)

    assert_button "Combine Duplicates", disabled: true
  end

  test "combine stays disabled when a merged transfer's origins no longer touch the shared bank" do
    duplicate = Transaction.create!(
      user: @user, src_account: accounts(:lunchflow_linked_asset), dest_account: accounts(:expense_account),
      amount_minor: 900, currency: currencies(:usd), description: "Moved charge",
      transacted_at: 1.day.ago
    )
    edited = merged_transfer(900)
    edited.update!(src_account: accounts(:lunchflow_linked_asset))

    visit transactions_path
    toggle_select(duplicate)
    toggle_select(edited)

    assert_button "Combine Duplicates", disabled: true
  end

  test "combine stays disabled when a selected row is a foreign-exchange transaction" do
    normal = manual_transaction("FX gate normal", 500)
    fx = Transaction.create!(
      user: @user, src_account: accounts(:asset_account), dest_account: accounts(:expense_account),
      amount_minor: 500, currency: currencies(:usd), description: "FX gate fx",
      transacted_at: 1.day.ago, fx_amount_minor: 400, fx_currency: currencies(:eur)
    )

    visit transactions_path
    toggle_select(normal)
    toggle_select(fx)

    assert_button "Combine Duplicates", disabled: true
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

  test "the merge preview shows an 18-decimal amount exactly" do
    eth = Currency.create!(name: "Ether", symbol: "Ξ", code: "ETH", decimal_places: 18, kind: :crypto, active: true)
    wallet = Account.create!(user: @user, currency: eth, name: "ETH Wallet", kind: :asset)
    exchange = Account.create!(user: @user, currency: eth, name: "ETH Exchange", kind: :asset)
    expense = Account.create!(user: @user, currency: eth, name: "ETH Outflow", kind: :expense)
    revenue = Account.create!(user: @user, currency: eth, name: "ETH Inflow", kind: :revenue)
    amount_minor = 10**21 + 1
    withdrawal = Transaction.create!(
      user: @user, src_account: exchange, dest_account: expense,
      amount_minor: amount_minor, currency: eth, description: "Transfer out", transacted_at: 1.day.ago
    )
    deposit = Transaction.create!(
      user: @user, src_account: revenue, dest_account: wallet,
      amount_minor: amount_minor, currency: eth, description: "Transfer in", transacted_at: 1.day.ago
    )

    visit transactions_path
    toggle_select(withdrawal)
    toggle_select(deposit)
    click_button "Merge into Transfer"

    within ".selection-confirmation:not([hidden])" do
      assert_text "ETH 1000.000000000000000001"
    end
  end

  test "the merge preview shows a zero-decimal currency without decimals" do
    jpy = currencies(:jpy)
    wallet = Account.create!(user: @user, currency: jpy, name: "JPY Wallet", kind: :asset)
    bank = Account.create!(user: @user, currency: jpy, name: "JPY Bank", kind: :asset)
    expense = Account.create!(user: @user, currency: jpy, name: "JPY Outflow", kind: :expense)
    revenue = Account.create!(user: @user, currency: jpy, name: "JPY Inflow", kind: :revenue)
    withdrawal = Transaction.create!(
      user: @user, src_account: bank, dest_account: expense,
      amount_minor: 1500, currency: jpy, description: "Transfer out", transacted_at: 1.day.ago
    )
    deposit = Transaction.create!(
      user: @user, src_account: revenue, dest_account: wallet,
      amount_minor: 1500, currency: jpy, description: "Transfer in", transacted_at: 1.day.ago
    )

    visit transactions_path
    toggle_select(withdrawal)
    toggle_select(deposit)
    click_button "Merge into Transfer"

    within ".selection-confirmation:not([hidden])" do
      assert_text "JPY 1500"
      assert_no_text "JPY 15.00"
    end
  end

  test "clicking a From cell enters edit mode on that field and Save confirms" do
    transaction = manual_transaction("Field edit probe", 1500)
    visit transactions_path

    within_row(transaction) do
      # The phone-only plain-text twins stay hidden on desktop.
      assert_no_selector ".cell-static"

      click_cell "transaction[src_account_id]"

      assert_selector ".edit select[name='transaction[src_account_id]']:focus"
      select accounts(:liability_account).name, from: "transaction[src_account_id]"
      click_button "Save"

      assert_no_selector ".transaction.editing"
      within(".row.show .account-cell", match: :first) { assert_text accounts(:liability_account).name }
    end

    assert_equal accounts(:liability_account), transaction.reload.src_account
  end

  test "Cancel discards changes made after clicking a field" do
    transaction = manual_transaction("Field cancel probe", 1500)
    visit transactions_path

    within_row(transaction) do
      click_cell "transaction[description]"

      assert_selector ".edit input[name='transaction[description]']:focus"
      fill_in "transaction[description]", with: "Never saved"
      click_link "Cancel"

      within(".row.show") { assert_text "Field cancel probe" }
    end

    assert_equal "Field cancel probe", transaction.reload.description
  end

  test "Escape discards changes made after clicking a field" do
    transaction = manual_transaction("Field escape probe", 1500)
    visit transactions_path

    within_row(transaction) do
      click_cell "transaction[amount]"

      field = find(".edit input[name='transaction[amount]']:focus")
      field.set("99.99")
      field.send_keys(:escape)

      within(".row.show") { assert_text "$15.00" }
      assert_equal "15.00", find("input[name='transaction[amount]']", visible: :all).value
    end

    assert_equal 1500, transaction.reload.amount_minor
  end

  test "edit mode keeps the row's source and Merged pills" do
    merged = merged_transfer(2500)
    visit transactions_path

    within_row(merged) do
      click_cell "transaction[description]"

      within(".edit") do
        assert_selector ".source-badge", text: "SimpleFIN"
        assert_selector ".merged-badge", text: "Merged"
      end
    end
  end

  test "clicking Cleared saves it at once without entering edit mode" do
    transaction = manual_transaction("Cleared toggle probe", 1500)
    visit transactions_path

    within_row(transaction) do
      find(".cleared-cell button[aria-pressed='false']").click

      assert_selector ".cleared-cell button[aria-pressed='true']", text: "✓"
      assert_no_selector ".transaction.editing"
    end
    assert_not_nil transaction.reload.cleared_at

    within_row(transaction) do
      find(".cleared-cell button[aria-pressed='true']").click

      assert_selector ".cleared-cell button[aria-pressed='false']"
    end
    assert_nil transaction.reload.cleared_at
  end

  # Chrome holds back the Escape that closes a list, so this guards the
  # behaviour rather than transactions--row#isOpenSelect specifically.
  test "Escape on an open account list closes the list before discarding the edit" do
    transaction = manual_transaction("List escape probe", 1500)
    visit transactions_path

    within_row(transaction) do
      click_cell "transaction[src_account_id]"
      select = find(".edit select[name='transaction[src_account_id]']:focus")
      assert evaluate_script("arguments[0].matches(':open')", select), "clicking From should open its list"

      select.send_keys(:escape)
      assert_selector ".transaction.editing"
      assert_not evaluate_script("arguments[0].matches(':open')", select)

      select.send_keys(:escape)
      assert_no_selector ".transaction.editing"
    end
  end

  test "an empty category cell opens edit mode on the category" do
    transaction = manual_transaction("Field category probe", 1500)
    visit transactions_path

    within_row(transaction) do
      click_cell "transaction[category_id]"

      assert_selector ".edit select[name='transaction[category_id]']:focus"
    end
  end

  test "sweeping the pointer across rows loads only the edit form it rests on" do
    rows = 4.times.map { |index| manual_transaction("Sweep probe #{index}", 100 + index) }
    visit transactions_path

    cells = rows.map { |transaction| within_row(transaction) { find(".description-cell .cell-edit").native } }
    # One uninterrupted pointer movement, as a real sweep is; separate
    # Capybara hovers each take longer than the preload delay.
    sweep = page.driver.browser.action
    cells.each { |cell| sweep.move_to(cell, duration: 0) }
    sweep.perform

    # Only the last row, where the pointer stays, loads its form.
    within_row(rows.last) { assert_selector ".edit form", visible: :all }
    rows[0..-2].each do |transaction|
      within_row(transaction) { assert_no_selector ".edit form", visible: :all }
    end
  end

  test "a rejected Cleared toggle opens edit mode with the errors" do
    transaction = manual_transaction("Rejected toggle probe", 1500)
    # Already invalid for another reason, so any save is rejected.
    transaction.update_columns(dest_account_id: transaction.src_account_id)
    visit transactions_path

    within_row(transaction) do
      find(".cleared-cell button").click

      assert_selector ".transaction.editing"
      within(".edit") { assert_text "Transaction could not be saved" }
    end
    assert_nil transaction.reload.cleared_at
  end

  test "a rejected edit's error box is painted below the row, not clipped by it" do
    transaction = manual_transaction("Clipped error probe", 1500)
    transaction.update_columns(dest_account_id: transaction.src_account_id)
    visit transactions_path

    within_row(transaction) do
      find(".cleared-cell button").click
      assert_selector ".edit .error", text: "Transaction could not be saved"
    end

    # Hit-testing follows paint, so the box is the topmost element at its own
    # centre only when nothing clips it.
    painted = page.evaluate_script(<<~JS)
      (() => {
        const error = document.querySelector(".transaction.editing .edit .error")
        error.scrollIntoView({ block: "center" })
        const box = error.getBoundingClientRect()
        return error.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
      })()
    JS
    assert painted
  end

  test "opening balances keep their cells as plain text" do
    opening_balance = transactions(:opening_balance_revenue)
    accept_confirm { click_link "Logout" }
    assert_link "Login"
    sign_in_as(opening_balance.user)

    visit transactions_path

    within_row(opening_balance) do
      assert_text "Opening Balance"
      assert_no_selector "button.cell-edit"
      open_row_menu
      assert_selector "[role=menuitem]", text: "Edit Account"
      assert_no_selector "[role=menuitem]", text: /\AEdit\z/
    end
  end

  test "on a phone rows are read-only until Edit is chosen" do
    transaction = manual_transaction("Phone read-only probe", 1500)
    cleared = manual_transaction("Phone cleared probe", 1600)
    cleared.update!(cleared: true)
    page.driver.browser.manage.window.resize_to(390, 900)
    visit transactions_path

    within_row(transaction) do
      # Hidden outright, so neither a tap, Tab, nor assistive technology can
      # reach a cell button or the Cleared toggle; plain text shows instead.
      assert_no_selector "button.cell-edit"
      assert_selector "button.cell-edit", visible: :hidden, minimum: 7
      within(".description-cell") { assert_selector ".cell-static", text: "Phone read-only probe" }
      within(".account-cell", match: :first) { assert_selector ".cell-static", text: accounts(:asset_account).name }

      open_row_menu
      click_link "Edit"
      assert_field "transaction[description]", with: "Phone read-only probe"
    end

    # A cleared row shows its tick as plain text, with the toggle hidden.
    within_row(cleared) do
      within(".cleared-cell") do
        assert_selector ".cell-static", text: "✓"
        assert_no_selector "button"
      end
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "on a phone the new-transaction form opens from its button" do
    page.driver.browser.manage.window.resize_to(390, 900)
    visit transactions_path

    assert_no_field "transaction[description]", visible: true
    click_button "New transaction"
    assert_field "transaction[description]"
    assert_selector ".new-transaction-toggle[aria-expanded='true']"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "a row's actions sit behind its kebab menu" do
    transaction = sourced_transaction("Kebab menu probe", 1200, :transaction_one)
    visit transactions_path

    within_row(transaction) do
      assert_no_link "Delete"
      trigger = find(ROW_MENU_TRIGGER)
      assert_equal "false", trigger["aria-expanded"]

      open_row_menu
      within("[role=menu]") do
        assert_equal %w[Edit Exclude Delete], all("[role=menuitem]").map(&:text)
      end
      assert_selector "#{ROW_MENU_TRIGGER}[aria-expanded='true']"
      # Focus moves into the menu (open_row_menu waits for it), and the arrow
      # keys walk its items.
      send_keys :arrow_down
      assert_selector "[role=menuitem]:focus", text: "Exclude"
      send_keys :arrow_up, :arrow_up
      assert_selector "[role=menuitem]:focus", text: "Delete"

      # Escape closes it and hands focus back to the trigger.
      send_keys :escape
      assert_no_selector "[role=menu]"
      # aria-expanded flips in the popover's toggle event, a moment after the
      # menu has gone, so wait for it rather than reading it once.
      assert_selector "#{ROW_MENU_TRIGGER}[aria-expanded='false']:focus"
    end
  end

  test "the menu opens already in place under its trigger" do
    transaction = manual_transaction("Menu placement probe", 1250)
    visit transactions_path

    # Show the popover and measure it in the same task, before the toggle
    # event (and any script placement) can run: CSS has to have placed it.
    within_row(transaction) do
      placement = page.evaluate_script(<<~JS)
        (() => {
          const trigger = document.querySelector("##{ActionView::RecordIdentifier.dom_id(transaction)} .menu-trigger")
          const menu = document.getElementById(trigger.getAttribute("popovertarget"))
          menu.showPopover()
          const triggerBox = trigger.getBoundingClientRect()
          const menuBox = menu.getBoundingClientRect()
          return { rightGap: triggerBox.right - menuBox.right, topGap: menuBox.top - triggerBox.bottom }
        })()
      JS

      assert_in_delta 0, placement["rightGap"], 1
      assert_in_delta 4, placement["topGap"], 1
    end
  end

  test "form actions are icon buttons on desktop and worded buttons on phones" do
    transaction = manual_transaction("Form actions probe", 1350)
    visit transactions_path

    within("#new_transaction") do
      assert_button "Create"
      assert_equal({ "icon" => true, "word" => false }, form_action_display("button[title='Create']"))
    end

    # The kebab and Create share a box, so their icons line up in the column.
    create_box, kebab_box = page.evaluate_script(<<~JS)
      ["#new_transaction .form-action", "##{ActionView::RecordIdentifier.dom_id(transaction)} .menu-trigger"].map((selector) => {
        const box = document.querySelector(selector).getBoundingClientRect()
        return [box.left, box.width, box.height]
      })
    JS
    create_box.zip(kebab_box).each { |create, kebab| assert_in_delta create, kebab, 0.5 }

    within_row(transaction) do
      open_row_menu
      click_link "Edit"
      assert_button "Save"
      assert_link "Cancel"
      assert_equal({ "icon" => true, "word" => false }, form_action_display("button[title='Save']"))
      assert_equal({ "icon" => true, "word" => false }, form_action_display("a[title='Cancel']"))
    end

    page.driver.browser.manage.window.resize_to(390, 900)
    within_row(transaction) do
      assert_equal({ "icon" => false, "word" => true }, form_action_display("button[title='Save']"))
      assert_equal({ "icon" => false, "word" => true }, form_action_display("a[title='Cancel']"))
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "the Actions column widens only while a row is being edited" do
    editing = manual_transaction("Column edit probe", 1360)
    watching = manual_transaction("Column watch probe", 1370)
    visit transactions_path

    assert_in_delta 45.9, actions_column_width(watching), 0.5

    within_row(editing) do
      open_row_menu
      click_link "Edit"
      assert_link "Cancel"
    end
    assert_in_delta 75.8, actions_column_width(watching), 0.5

    # Save and Cancel fill the cell exactly: Cancel ends at the padding.
    gap = page.evaluate_script(<<~JS)
      (() => {
        const row = document.querySelector("##{ActionView::RecordIdentifier.dom_id(editing)} form .row")
        const cell = row.querySelector(".actions").getBoundingClientRect()
        const cancel = row.querySelector("a[title='Cancel']").getBoundingClientRect()
        return cell.right - cancel.right
      })()
    JS
    assert_in_delta 10, gap, 0.5

    within_row(editing) { click_link "Cancel" }
    assert_in_delta 45.9, actions_column_width(watching), 0.5
  end

  test "the row keeps its height while the edit form loads" do
    transaction = sourced_transaction("Loading height probe", 1380, :transaction_one)
    visit transactions_path
    row_selector = "##{ActionView::RecordIdentifier.dom_id(transaction)} .transaction"
    frame_selector = "##{ActionView::RecordIdentifier.dom_id(transaction, :edit)}"

    # Hold the form back: with no src, the frame can't load until it gets one.
    source = page.evaluate_script(<<~JS)
      (() => {
        const frame = document.querySelector("#{frame_selector}")
        const source = frame.getAttribute("src")
        frame.removeAttribute("src")
        return source
      })()
    JS
    height = -> { page.evaluate_script("document.querySelector('#{row_selector}').getBoundingClientRect().height") }
    resting_height = height.call

    within_row(transaction) do
      open_row_menu
      click_link "Edit"
      assert_selector ".transaction.editing"
      # The shown row stays put, marked busy, at the same height.
      assert_selector ".row.show", text: "Loading height probe"
      assert_equal "progress", page.evaluate_script("getComputedStyle(document.querySelector('#{row_selector} .row.show')).cursor")
    end
    assert_in_delta resting_height, height.call, 0.5

    page.execute_script("document.querySelector('#{frame_selector}').setAttribute('src', '#{source}')")
    within_row(transaction) do
      assert_field "transaction[description]", with: "Loading height probe"
      assert_no_selector ".row.show"
    end
  end

  test "on a short viewport the menu stays on screen when it fits on neither side of its trigger" do
    transaction = sourced_transaction("Short viewport probe", 1390, :transaction_one)
    visit transactions_path
    with_short_viewport(transaction) do
      within_row(transaction) { open_row_menu }
      assert_row_menu_in_viewport(transaction)
    end
  end

  test "script placement keeps the menu on screen on a short viewport" do
    transaction = sourced_transaction("Short viewport script probe", 1395, :transaction_one)
    visit transactions_path
    # Take the fallback path the controller uses without anchor positioning,
    # and cancel the CSS anchoring so only the script places the menu.
    page.execute_script(<<~JS)
      (() => {
        const actions = document.querySelector("##{ActionView::RecordIdentifier.dom_id(transaction)} .row.show > .actions")
        window.Stimulus.getControllerForElementAndIdentifier(actions, "menu").constructor.anchorPositioning = false
        const style = document.createElement("style")
        style.textContent = "html body .transactions .menu[popover] { position-try-fallbacks: none; top: 0; right: auto; left: 0; }"
        document.head.append(style)
      })()
    JS
    with_short_viewport(transaction) do
      within_row(transaction) { open_row_menu }
      assert_row_menu_in_viewport(transaction)
    end
  end

  test "choosing Edit from the menu closes it and opens the edit form" do
    transaction = manual_transaction("Menu edit probe", 1300)
    visit transactions_path

    within_row(transaction) do
      open_row_menu
      click_link "Edit"
      assert_field "transaction[description]", with: "Menu edit probe"
    end
    # Edit hides the shown row, menu and all, so check the popover itself.
    assert_not row_menu_open?(transaction)
  end

  test "choosing Edit by keyboard puts focus in the edit form" do
    transaction = manual_transaction("Keyboard edit probe", 1310)
    visit transactions_path

    within_row(transaction) do
      open_row_menu(by: :keyboard)
      send_keys :enter # on Edit, focused when the menu opened
      assert_field "transaction[description]", with: "Keyboard edit probe"
    end
    assert_not row_menu_open?(transaction)
    # Focus lands from the frame's load handler, which can run just after the
    # field shows, so wait for it.
    within_row(transaction) { assert_selector "input[name='transaction[transacted_at]']:focus" }
  end

  test "Space chooses the focused menu item" do
    transaction = manual_transaction("Space edit probe", 1320)
    visit transactions_path

    within_row(transaction) do
      open_row_menu(by: :keyboard)
      send_keys :space
      assert_field "transaction[description]", with: "Space edit probe"
    end
  end

  test "a keyboard-focused menu item shows the focus ring in the dark theme" do
    transaction = sourced_transaction("Focus ring probe", 1330, :transaction_one)
    visit transactions_path
    page.execute_script("document.documentElement.dataset.theme = 'dark'")

    within_row(transaction) do
      open_row_menu(by: :keyboard)
      send_keys :arrow_down
      assert_selector "[role=menuitem]:focus", text: "Exclude"
    end
    outline = page.evaluate_script(<<~JS)
      (() => {
        const style = getComputedStyle(document.activeElement)
        return [document.activeElement.textContent.trim(), style.outlineStyle, style.outlineWidth]
      })()
    JS
    assert_equal [ "Exclude", "solid", "2px" ], outline
  end

  test "a trigger restored with a stale aria-expanded is reset when it reconnects" do
    transaction = manual_transaction("Stale expanded probe", 1340)
    visit transactions_path

    # What Turbo's cache hands back after a page is cached with a menu open:
    # the trigger still says expanded, but the popover is closed.
    page.execute_script(<<~JS)
      (() => {
        const actions = document.querySelector("##{ActionView::RecordIdentifier.dom_id(transaction)} .row.show > .actions")
        const copy = actions.cloneNode(true)
        copy.querySelector(".menu-trigger").setAttribute("aria-expanded", "true")
        actions.replaceWith(copy)
      })()
    JS

    within_row(transaction) do
      assert_selector "#{ROW_MENU_TRIGGER}[aria-expanded='false']"
    end
  end

  test "deleting from the menu removes the row" do
    transaction = manual_transaction("Menu delete probe", 1400)
    visit transactions_path

    within_row(transaction) do
      open_row_menu
      accept_confirm("Delete this transaction?") { click_link "Delete" }
    end

    assert_no_text "Menu delete probe"
  end

  test "an excluded row's menu offers Restore instead of Exclude" do
    transaction = sourced_transaction("Menu restore probe", 1600, :transaction_one)
    transaction.update!(excluded_at: Time.current)
    visit transactions_path(show_excluded: 1)

    within_row(transaction) do
      open_row_menu
      within("[role=menu]") do
        assert_link "Restore"
        assert_no_link "Exclude"
        assert_no_link "Unmerge"
      end
    end
  end

  test "scrolling to the foot of the list loads the next page" do
    account = accounts(:liability_account)
    paged_rows(account, 50)

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)

      assert_text "Paged row 01"
      assert_no_text "Paged row 50"

      scroll_to find(".transactions-page")

      assert_text "Paged row 50"
      assert_selector ".transaction", count: 50
      assert_no_link "Load more transactions"
    end
  end

  test "a transaction older than every loaded row arrives with its page, once" do
    account = accounts(:liability_account)
    paged_rows(account, 50)

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)
      assert_text "Paged row 01"

      fill_in "transaction[transacted_at]", with: Time.zone.parse("2020-01-01 10:00")
      fill_in "transaction[description]", with: "Backdated probe"
      select account.name, from: "transaction[src_account_id]"
      select accounts(:expense_account).name, from: "transaction[dest_account_id]"
      fill_in "transaction[amount]", with: "3.00"
      click_button "Create"

      # The form resets once the create lands; the row's page isn't loaded yet.
      assert_field "transaction[description]", with: ""
      assert_no_text "Backdated probe"

      scroll_to find(".transactions-page")

      assert_selector ".transaction", text: "Backdated probe", count: 1
    end
  end

  test "an unmerged leg that sorts below the loaded rows arrives with its page, once" do
    account = accounts(:liability_account)
    paged_rows(account, 50)
    currency = currencies(:usd)
    withdrawal = Transaction.create!(user: @user, src_account: account, dest_account: accounts(:expense_account),
                                     amount_minor: 700, currency: currency, description: "Old withdrawal leg",
                                     transacted_at: Time.zone.parse("2020-01-01 10:00"))
    deposit = Transaction.create!(user: @user, src_account: accounts(:revenue_account), dest_account: accounts(:asset_account),
                                  amount_minor: 700, currency: currency, description: "Old deposit leg",
                                  transacted_at: Time.zone.parse("2020-01-01 10:00"))
    merger = Transaction::Merge.new(withdrawal, deposit, user: @user, transacted_at: Time.current)
    assert merger.call
    merged = merger.merged_transaction

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)

      within_row(merged) do
        open_row_menu
        accept_confirm { click_link "Unmerge" }
      end

      assert_no_selector "##{ActionView::RecordIdentifier.dom_id(merged)}"
      assert_no_text "Old withdrawal leg"

      scroll_to find(".transactions-page")

      assert_selector ".transaction", text: "Old withdrawal leg", count: 1
    end
  end

  test "a row whose new date sorts below the loaded rows leaves and arrives with its page, once" do
    account = accounts(:liability_account)
    paged_rows(account, 50)
    moved = @user.transactions.find_by!(description: "Paged row 03")

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)

      within_row(moved) { find(".date-cell .cell-edit").click }
      within_row(moved) do
        fill_in "transaction[transacted_at]", with: Time.zone.parse("2020-01-01 10:00")
        click_button "Save"
      end

      assert_no_text "Paged row 03"

      scroll_to find(".transactions-page")

      assert_selector ".transaction", text: "Paged row 03", count: 1
      assert_selector ".transaction", count: 50
    end
  end

  test "a date edit on the transaction's own page keeps it on screen" do
    transaction = manual_transaction("Standalone date probe", 1500)
    visit transaction_path(transaction)

    # show.html.erb wraps the row in a frame sharing its id, so scope by class.
    find(".transaction .date-cell .cell-edit").click
    within(".transaction") do
      fill_in "transaction[transacted_at]", with: Time.zone.parse("2020-01-01 10:00")
      click_button "Save"
    end

    assert_selector ".transaction .date-cell", text: "2020-01-01"
    assert_text "Standalone date probe"
  end

  test "the next page starts from the top once every loaded row is gone" do
    account = accounts(:liability_account)
    paged_rows(account, 50)

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)
      assert_text "Paged row 01"

      # What the delete streams do, without scrolling the next page into view.
      loaded = @user.transactions.where(description: (1..40).map { |index| format("Paged row %02d", index) })
      page.execute_script("document.querySelectorAll('#transactions [data-page-cursor]').forEach((row) => row.closest('turbo-frame').remove())")
      loaded.destroy_all
      # Sorts inside the range that was loaded, above the frame's own cursor
      # (row 40), so only a restart from the top finds it.
      Transaction.create!(user: @user, src_account: account, dest_account: accounts(:expense_account),
                          amount_minor: 100, currency: currencies(:usd), description: "Restart probe",
                          transacted_at: 10.days.ago)

      scroll_to find(".transactions-page")

      assert_text "Restart probe"
      assert_text "Paged row 41"
      assert_text "Paged row 50"
      assert_selector ".transaction", count: 11
    end
  end

  test "a row added where the last loaded row was still loads with the next page" do
    account = accounts(:liability_account)
    paged_rows(account, 50)
    last_loaded = @user.transactions.find_by!(description: "Paged row 40")
    gap_time = last_loaded.transacted_at

    Transaction::Page.stub(:size, 40) do
      visit account_transactions_path(account)

      assert_text "Paged row 01"
      # What the Delete action's stream does, without scrolling to the row:
      # that would bring the next page into view and load it straight away.
      last_loaded.destroy!
      page.execute_script("document.getElementById('#{ActionView::RecordIdentifier.dom_id(last_loaded)}').remove()")
      assert_no_text "Paged row 40"

      # Sorts just above where the deleted row was (same date, created later),
      # so below every row still loaded: it belongs to the next page.
      Transaction.create!(user: @user, src_account: account, dest_account: accounts(:expense_account),
                          amount_minor: 100, currency: currencies(:usd), description: "Gap probe",
                          transacted_at: gap_time)

      scroll_to find(".transactions-page")

      assert_selector ".transaction", text: "Gap probe", count: 1
      assert_text "Paged row 50"
    end
  end

  test "an outside click closes the menu" do
    transaction = manual_transaction("Menu dismiss probe", 1700)
    visit transactions_path

    within_row(transaction) { open_row_menu }
    assert_selector "[role=menu]"
    find("h1, header", match: :first).click
    assert_no_selector "[role=menu]"
  end

  private

  ROW_MENU_TRIGGER = "button[aria-label='Transaction actions']".freeze

  # `count` rows in `account`'s list, "Paged row 01" the newest, one day apart.
  def paged_rows(account, count)
    count.times do |index|
      Transaction.create!(user: @user, src_account: account, dest_account: accounts(:expense_account),
                          amount_minor: 100, currency: currencies(:usd),
                          description: format("Paged row %02d", index + 1), transacted_at: (index + 1).days.ago)
    end
  end

  # Open the row's kebab menu; call inside within_row.
  # Open the row's kebab menu, by click or by Enter on the trigger; call
  # inside within_row. The menu focuses its first item from its toggle event,
  # a moment after it shows, so wait for that focus: a key sent before it
  # lands on the trigger and closes the menu again.
  def open_row_menu(by: :click)
    trigger = find(ROW_MENU_TRIGGER)
    by == :keyboard ? trigger.send_keys(:enter) : trigger.click
    assert_selector "[role=menuitem]:focus", text: /\AEdit/
  end

  # Which of a form action's two faces is showing: the icon, or the word
  # (which, when hidden, is clipped to a 1px box for screen readers).
  def form_action_display(selector)
    action = find(selector)
    page.evaluate_script(<<~JS, action)
      ((action) => ({
        icon: getComputedStyle(action.querySelector("svg")).display !== "none",
        word: action.querySelector(".form-action__label").getBoundingClientRect().width > 1
      }))(arguments[0])
    JS
  end

  # A viewport too short for the row's menu to fit below or above its
  # trigger, with the row scrolled to the middle of it.
  def with_short_viewport(transaction)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1400, height: 220, deviceScaleFactor: 1, mobile: false)
    page.execute_script("document.getElementById('#{ActionView::RecordIdentifier.dom_id(transaction)}').scrollIntoView({ block: 'center' })")
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def assert_row_menu_in_viewport(transaction)
    box = page.evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector("##{ActionView::RecordIdentifier.dom_id(transaction)} .menu-trigger")
        const menu = document.getElementById("#{ActionView::RecordIdentifier.dom_id(transaction, :actions_menu)}")
        const triggerBox = trigger.getBoundingClientRect()
        const menuBox = menu.getBoundingClientRect()
        return { top: menuBox.top, bottom: menuBox.bottom, height: menuBox.height, viewport: window.innerHeight,
                 below: window.innerHeight - triggerBox.bottom, above: triggerBox.top }
      })()
    JS
    # The setup really is the hard case: no room on either side...
    assert_operator box["below"], :<, box["height"]
    assert_operator box["above"], :<, box["height"]
    # ...yet the whole menu is on screen.
    assert_operator box["top"], :>=, 0
    assert_operator box["bottom"], :<=, box["viewport"]
  end

  def row_menu_open?(transaction)
    page.evaluate_script(<<~JS)
      document.getElementById("#{ActionView::RecordIdentifier.dom_id(transaction, :actions_menu)}").matches(":popover-open")
    JS
  end

  def actions_column_width(transaction)
    page.evaluate_script(<<~JS)
      document.querySelector("##{ActionView::RecordIdentifier.dom_id(transaction)} .row.show > .actions").getBoundingClientRect().width
    JS
  end

  def within_row(transaction, &block)
    within("##{ActionView::RecordIdentifier.dom_id(transaction)}", &block)
  end

  # Hover the cell, as a person would (which starts loading the edit form),
  # then click it.
  def click_cell(field)
    cell = find("button[data-field='#{field}']")
    cell.hover
    cell.click
  end

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

  # A merge result on the same bank as manual_transaction: a sourced
  # asset_account → expense withdrawal merged with a revenue → linked_asset deposit.
  def merged_transfer(amount_minor)
    withdrawal = sourced_transaction("Posted charge", amount_minor, :transaction_one)
    deposit = Transaction.create!(
      user: @user, src_account: accounts(:revenue_account), dest_account: accounts(:linked_asset),
      amount_minor: amount_minor, currency: currencies(:usd), description: "Posted deposit",
      transacted_at: 1.day.ago
    )
    merge = Transaction::Merge.new(withdrawal, deposit, user: @user)
    assert merge.call, merge.errors.inspect
    merge.merged_transaction
  end

  def toggle_select(transaction)
    find("input.selection-checkbox[data-transaction-id='#{transaction.id}']").click
  end
end
