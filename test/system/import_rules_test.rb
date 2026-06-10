require "application_system_test_case"

class ImportRulesTest < ApplicationSystemTestCase
  include ActionView::RecordIdentifier

  setup do
    @user = users(:one)
    @user.update!(password: "password123")
    sign_in_as(@user)
  end

  test "create a rule inline in the workbench" do
    visit import_rules_path
    click_on "New rule"

    within "#rule_editor" do
      fill_in "Pattern", with: "grocery"
      choose "Starts", allow_label_click: true
      select "Expense Account", from: "Account"
      click_button "Create rule"
    end

    within "#ir_list" do
      assert_text "grocery"
      assert_text "Expense Account"
    end
    # The just-created rule stays open in the editor.
    within("#rule_editor") { assert_field "Pattern", with: "grocery" }
  end

  test "create an exclude rule without an account" do
    visit import_rules_path
    click_on "New rule"

    within "#rule_editor" do
      fill_in "Pattern", with: "internal transfer"
      choose "Exclude", allow_label_click: true
      click_button "Create rule"
    end

    within "#ir_list" do
      assert_text "internal transfer"
      assert_text "Exclude"
    end
  end

  test "toggling to exclude and back restores the chosen account" do
    visit import_rules_path
    click_on "New rule"

    within "#rule_editor" do
      fill_in "Pattern", with: "restore me"
      select "Expense Account", from: "Account"

      choose "Exclude", allow_label_click: true
      choose "Assign to account", allow_label_click: true

      assert page.has_select?("Account", selected: "Expense Account")
    end
  end

  test "edit a rule inline and highlight the selected row" do
    visit import_rules_path
    rule_row = "##{dom_id(import_rules(:fixture_rule_one))}"

    within(rule_row) { click_on "FIXTURE_PATTERN_ONE" }
    assert_selector "#{rule_row}.ir-rule--selected"

    within "#rule_editor" do
      fill_in "Pattern", with: "UPDATED_PATTERN"
      click_button "Save changes"
    end

    within "#ir_list" do
      assert_text "UPDATED_PATTERN"
      assert_no_text "FIXTURE_PATTERN_ONE"
    end
    # The editor stays open on the saved rule, with its row still highlighted.
    within("#rule_editor") { assert_field "Pattern", with: "UPDATED_PATTERN" }
    assert_selector "#{rule_row}.ir-rule--selected"
  end

  test "delete a rule from the editor" do
    visit import_rules_path
    assert_text "FIXTURE_PATTERN_ONE"

    within("##{dom_id(import_rules(:fixture_rule_one))}") { click_on "FIXTURE_PATTERN_ONE" }
    within "#rule_editor" do
      accept_confirm("Delete this rule?") { click_on "Delete" }
    end

    assert_no_text "FIXTURE_PATTERN_ONE"
  end

  test "live preview shows matching ledger transactions as you type" do
    expense = Account.create!(user: @user, currency: currencies(:usd), name: "Coffee", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "sys_live_1",
      amount: "-5.00", description: "BLUEBOTTLE COFFEE", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: expense, amount_minor: 500,
      currency: currencies(:usd), description: "BLUEBOTTLE COFFEE", transacted_at: 1.day.ago, sourceable: source
    )

    visit import_rules_path
    click_on "New rule"

    within "#rule_editor" do
      fill_in "Pattern", with: "BLUEBOTTLE"
    end

    within "#ir_match_preview" do
      assert_text "BLUEBOTTLE COFFEE"
      assert_text "1 match"
    end
  end

  test "editing a rule preloads its live matches" do
    misc = Account.create!(user: @user, currency: currencies(:usd), name: "Misc Preload", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "sys_preload",
      amount: "-6.00", description: "PRELOADSYS CAFE", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: misc, amount_minor: 600,
      currency: currencies(:usd), description: "PRELOADSYS CAFE", transacted_at: 1.day.ago, sourceable: source
    )
    rule = ImportRule.create!(user: @user, account: accounts(:expense_account), match_pattern: "PRELOADSYS", match_type: :contains)

    visit import_rules_path
    within("##{dom_id(rule)}") { click_on "PRELOADSYS" }

    # The match shows immediately, without typing (the frame is rendered server-side).
    within("#ir_match_preview") { assert_text "PRELOADSYS CAFE" }
  end

  test "filter the list with search" do
    visit import_rules_path
    assert_text "FIXTURE_PATTERN_ONE"
    assert_text "FIXTURE_PATTERN_TWO"

    fill_in "ir_search", with: "PATTERN_ONE"

    assert_text "FIXTURE_PATTERN_ONE"
    assert_no_text "FIXTURE_PATTERN_TWO"
  end

  test "filter the list by exclude action" do
    visit import_rules_path

    within(".ir-seg") { click_on "Exclude" }

    assert_text "FIXTURE_EXCLUDE_PATTERN"
    assert_no_text "FIXTURE_PATTERN_ONE"
  end

  test "open the per-rule preview modal from the editor" do
    visit import_rules_path

    within("##{dom_id(import_rules(:fixture_rule_one))}") { click_on "FIXTURE_PATTERN_ONE" }
    within("#rule_editor") { click_on "Preview" }

    within "#preview_modal_frame" do
      assert_text "Preview rule"
      # Unedited rule that matches nothing: a clean "no changes" state, no save prompt.
      assert_text "No changes needed"
    end
  end

  test "preview a brand-new rule before saving it" do
    misc = Account.create!(user: @user, currency: currencies(:usd), name: "Misc", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "sys_draft_1",
      amount: "-9.99", description: "DRAFTPREVIEW SHOP", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: misc, amount_minor: 999,
      currency: currencies(:usd), description: "DRAFTPREVIEW SHOP", transacted_at: 1.day.ago, sourceable: source
    )

    visit import_rules_path
    click_on "New rule"

    within "#rule_editor" do
      fill_in "Pattern", with: "DRAFTPREVIEW"
      select "Expense Account", from: "Account"
      click_on "Preview"
    end

    within "#preview_modal_frame" do
      assert_text "Preview rule"
      assert_text "DRAFTPREVIEW SHOP"
      # A brand-new rule has unsaved edits, so the modal offers to save while applying.
      assert_text "Save & apply 1 change"
    end
  end

  test "previewing an unedited saved rule offers a plain Apply" do
    misc = Account.create!(user: @user, currency: currencies(:usd), name: "Misc Clean", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "sys_clean",
      amount: "-4.00", description: "CLEANRULE SHOP", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: misc, amount_minor: 400,
      currency: currencies(:usd), description: "CLEANRULE SHOP", transacted_at: 1.day.ago, sourceable: source
    )
    rule = ImportRule.create!(user: @user, account: accounts(:expense_account), match_pattern: "CLEANRULE", match_type: :contains)

    visit import_rules_path
    within("##{dom_id(rule)}") { click_on "CLEANRULE" }
    within("#rule_editor") { click_on "Preview" }

    within "#preview_modal_frame" do
      assert_text "Apply 1 change"
      assert_no_text "Save & apply"
      assert_text "Review the changes above"
    end
  end

  test "applying from the preview modal saves the rule and reassigns transactions" do
    misc = Account.create!(user: @user, currency: currencies(:usd), name: "Misc", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "sys_apply_save",
      amount: "-9.99", description: "APPLYSAVE SHOP", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: misc, amount_minor: 999,
      currency: currencies(:usd), description: "APPLYSAVE SHOP", transacted_at: 1.day.ago, sourceable: source
    )

    visit import_rules_path
    click_on "New rule"
    within "#rule_editor" do
      fill_in "Pattern", with: "APPLYSAVE"
      select "Expense Account", from: "Account"
      click_on "Preview"
    end

    # A new rule is dirty, so the modal's primary action saves and applies.
    within("#preview_modal_frame") { click_on "Save & apply 1 change" }

    # The rule is persisted (shows in the list) and the flash confirms the reassignment.
    within("#ir_list") { assert_text "APPLYSAVE" }
    assert_text "reassigned"
    assert ImportRule.exists?(user: @user, match_pattern: "APPLYSAVE")
  end

  test "open the preview and apply all modal" do
    visit import_rules_path
    click_on "Preview & apply all"

    within "#preview_modal_frame" do
      assert_text "Preview & apply all rules"
    end
  end

  test "user cannot see another user's import rules" do
    visit import_rules_path
    assert_text "FIXTURE_PATTERN_ONE"

    Capybara.reset_sessions!
    user_two = users(:two)
    user_two.update!(password: "password123")
    sign_in_as(user_two)

    visit import_rules_path
    assert_no_text "FIXTURE_PATTERN_ONE"
    assert_no_text "FIXTURE_PATTERN_TWO"
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
