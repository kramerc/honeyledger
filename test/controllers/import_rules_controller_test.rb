require "test_helper"

class ImportRulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @import_rule = import_rules(:fixture_rule_one)
  end

  test "should get index" do
    get import_rules_url
    assert_response :success
  end

  test "should get new" do
    get new_import_rule_url
    assert_response :success
  end

  test "should create import_rule" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "New Pattern",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }
    end

    assert_redirected_to import_rules_path
  end

  test "should get edit" do
    get edit_import_rule_url(@import_rule)
    assert_response :success
  end

  test "should update import_rule" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: "Updated Pattern",
      priority: 5
    } }
    assert_redirected_to import_rules_path
    @import_rule.reload
    assert_equal "Updated Pattern", @import_rule.match_pattern
    assert_equal 5, @import_rule.priority
  end

  test "should destroy import_rule" do
    assert_difference("ImportRule.count", -1) do
      delete import_rule_url(@import_rule)
    end

    assert_redirected_to import_rules_path
  end

  test "should not access other users rules" do
    other_user = users(:two)
    other_account = Account.create!(user: other_user, currency: currencies(:usd), name: "Other Expense", kind: :expense)
    other_rule = ImportRule.create!(user: other_user, account: other_account, match_pattern: "Other")

    get edit_import_rule_url(other_rule)
    assert_response :not_found
  end

  test "should create import_rule as json" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "JSON Pattern",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :created
  end

  test "should update import_rule as json" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: "JSON Updated"
    } }, as: :json
    assert_response :ok
  end

  test "should destroy import_rule as json" do
    assert_difference("ImportRule.count", -1) do
      delete import_rule_url(@import_rule), as: :json
    end

    assert_response :no_content
  end

  test "should not update with invalid params" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: ""
    } }
    assert_response :unprocessable_entity
  end

  test "should not update with invalid params as json" do
    patch import_rule_url(@import_rule), params: { import_rule: {
      match_pattern: ""
    } }, as: :json
    assert_response :unprocessable_entity
  end

  test "should not create rule with invalid params" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }
    end

    assert_response :unprocessable_entity
  end

  test "should not create rule with invalid params as json" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "",
        match_type: "contains",
        account_id: accounts(:expense_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "should create rule with asset account as json" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Transfer",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }, as: :json
    end

    assert_response :created
  end

  test "should get preview_apply" do
    get preview_apply_import_rules_url
    assert_response :success
  end

  test "should apply rules and redirect" do
    # Create an imported transaction that a rule would recategorize
    bank = accounts(:linked_asset)
    old_expense = Account.create!(user: @user, currency: currencies(:usd), name: "Old Category", kind: :expense)
    new_expense = Account.create!(user: @user, currency: currencies(:usd), name: "Apply Target", kind: :expense)

    create_sourced_transaction(
      user: @user,
      src_account: bank,
      dest_account: old_expense,
      amount_minor: 1000,
      currency: currencies(:usd),
      description: "APPLY_TEST_PATTERN",
      transacted_at: 1.day.ago,
      sourceable: simplefin_transactions(:transaction_one)
    )

    ImportRule.create!(
      user: @user,
      account: new_expense,
      match_pattern: "APPLY_TEST_PATTERN",
      match_type: :exact,
      priority: 100
    )

    post apply_import_rules_url
    assert_redirected_to import_rules_path
    assert_match(/reassigned/, flash[:notice])
  end

  test "should redirect with alert on apply error" do
    service_mock = Minitest::Mock.new
    service_mock.expect(:apply, 0)
    service_mock.expect(:errors, [ "Something went wrong" ])
    service_mock.expect(:errors, [ "Something went wrong" ])

    ImportRule::RetroactiveApply.stub(:new, service_mock) do
      post apply_import_rules_url
      assert_redirected_to preview_apply_import_rules_path
      assert_equal "Something went wrong", flash[:alert]
    end
  end

  test "should apply with no changes" do
    post apply_import_rules_url
    assert_redirected_to import_rules_path
  end

  test "preview of an edited draft rule offers to save it" do
    get preview_import_rules_url, params: {
      pattern: "NOMATCH_PATTERN_XYZ", match_type: "contains", account_id: accounts(:expense_account).id
    }
    assert_response :success
    assert_match "saved yet", @response.body
    assert_match "Save rule", @response.body
  end

  test "preview of an unchanged saved rule does not offer to save it" do
    rule = import_rules(:fixture_rule_one)
    get preview_import_rules_url, params: {
      id: rule.id, pattern: rule.match_pattern, match_type: rule.match_type, account_id: rule.account_id, exclude: false
    }
    assert_response :success
    assert_match "No changes needed", @response.body
    assert_no_match "Save rule", @response.body
  end

  test "should create rule with asset account" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "Transfer",
        match_type: "contains",
        account_id: accounts(:asset_account).id,
        priority: 0
      } }
    end

    assert_redirected_to import_rules_path
  end

  test "should place a new rule at the top priority when none is given" do
    top = current_user_top_priority
    post import_rules_url, params: { import_rule: {
      match_pattern: "TopOfStack",
      match_type: "contains",
      account_id: accounts(:expense_account).id
    } }
    assert_redirected_to import_rules_path
    assert_equal top + 1, ImportRule.find_by(match_pattern: "TopOfStack").priority
  end

  test "should create import_rule via turbo_stream" do
    assert_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: {
        match_pattern: "TurboNew", match_type: "contains", account_id: accounts(:expense_account).id
      } }, as: :turbo_stream
    end

    assert_response :success
    assert_match "ir_list", @response.body
    assert_match "rule_editor", @response.body
  end

  test "should re-render the editor on invalid turbo_stream create" do
    assert_no_difference("ImportRule.count") do
      post import_rules_url, params: { import_rule: { match_pattern: "" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "rule_editor", @response.body
  end

  test "should update import_rule via turbo_stream" do
    patch import_rule_url(@import_rule), params: { import_rule: { match_pattern: "TurboUpdated" } }, as: :turbo_stream
    assert_response :success
    assert_match "ir_list", @response.body
    assert_equal "TurboUpdated", @import_rule.reload.match_pattern
  end

  test "should destroy import_rule via turbo_stream" do
    assert_difference("ImportRule.count", -1) do
      delete import_rule_url(@import_rule), as: :turbo_stream
    end

    assert_response :success
    assert_match "ir_list", @response.body
  end

  test "should apply via turbo_stream" do
    post apply_import_rules_url, as: :turbo_stream
    assert_response :success
  end

  test "should reorder rules and reassign priority" do
    first = import_rules(:fixture_rule_one)
    second = import_rules(:fixture_rule_two)

    post reorder_import_rules_url, params: { ids: [ second.id, first.id ] }

    assert_response :no_content
    assert_operator second.reload.priority, :>, first.reload.priority
  end

  test "should ignore another user's rules when reordering" do
    other_user = users(:two)
    other_account = Account.create!(user: other_user, currency: currencies(:usd), name: "Other Reorder", kind: :expense)
    other_rule = ImportRule.create!(user: other_user, account: other_account, match_pattern: "OtherReorder")
    original_priority = other_rule.priority

    post reorder_import_rules_url, params: { ids: [ other_rule.id ] }

    assert_response :no_content
    assert_equal original_priority, other_rule.reload.priority
  end

  test "should return live matches from match_preview" do
    bank = accounts(:linked_asset)
    expense = Account.create!(user: @user, currency: currencies(:usd), name: "MP Expense", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "ctrl_mp_1",
      amount: "-12.00", description: "MATCHPREVIEW COFFEE", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: bank, dest_account: expense, amount_minor: 1200,
      currency: currencies(:usd), description: "MATCHPREVIEW COFFEE", transacted_at: 1.day.ago, sourceable: source
    )

    get match_preview_import_rules_url, params: { pattern: "MATCHPREVIEW", match_type: "contains" }

    assert_response :success
    # The matched substring is wrapped in <mark>, so assert on the highlight + plain remainder.
    assert_match %r{<mark class="ir-mark">MATCHPREVIEW</mark> COFFEE}, @response.body
  end

  test "match_preview with a blank pattern prompts for input" do
    get match_preview_import_rules_url, params: { pattern: "" }

    assert_response :success
    assert_match "Start typing", @response.body
  end

  test "match_preview lists already-excluded transactions" do
    bank = accounts(:linked_asset)
    expense = Account.create!(user: @user, currency: currencies(:usd), name: "Excl Cat", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "ctrl_excl",
      amount: "-3.00", description: "EXCLUDEDITEM SHOP", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    transaction = create_sourced_transaction(
      user: @user, src_account: bank, dest_account: expense, amount_minor: 300,
      currency: currencies(:usd), description: "EXCLUDEDITEM SHOP", transacted_at: 1.day.ago, sourceable: source
    )
    transaction.update_columns(excluded_at: Time.current)

    get match_preview_import_rules_url, params: { pattern: "EXCLUDEDITEM", match_type: "contains", exclude: "true" }

    assert_response :success
    assert_match %r{<mark class="ir-mark">EXCLUDEDITEM</mark> SHOP}, @response.body
    assert_match "ir-test__row--excluded", @response.body
    assert_match "ir-test__excluded", @response.body
  end

  test "edit preloads the live preview with the rule's matches" do
    rule = ImportRule.create!(user: @user, account: accounts(:expense_account), match_pattern: "PRELOADME", match_type: :contains)
    expense = Account.create!(user: @user, currency: currencies(:usd), name: "Preload Cat", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "ctrl_preload",
      amount: "-5.00", description: "PRELOADME CAFE", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    create_sourced_transaction(
      user: @user, src_account: accounts(:linked_asset), dest_account: expense, amount_minor: 500,
      currency: currencies(:usd), description: "PRELOADME CAFE", transacted_at: 1.day.ago, sourceable: source
    )

    get edit_import_rule_url(rule)

    assert_response :success
    assert_match %r{<mark class="ir-mark">PRELOADME</mark> CAFE}, @response.body
  end

  test "should create a rule and apply it retroactively when flagged" do
    bank = accounts(:linked_asset)
    old_category = Account.create!(user: @user, currency: currencies(:usd), name: "Old Cat", kind: :expense)
    new_category = Account.create!(user: @user, currency: currencies(:usd), name: "New Cat", kind: :expense)
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "ctrl_apply_save",
      amount: "-7.00", description: "SAVEAPPLY ITEM", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    transaction = create_sourced_transaction(
      user: @user, src_account: bank, dest_account: old_category, amount_minor: 700,
      currency: currencies(:usd), description: "SAVEAPPLY ITEM", transacted_at: 1.day.ago, sourceable: source
    )

    assert_difference("ImportRule.count") do
      post import_rules_url, params: {
        apply_after_save: "1",
        import_rule: { match_pattern: "SAVEAPPLY", match_type: "contains", account_id: new_category.id }
      }
    end

    assert_redirected_to import_rules_path
    assert_match(/reassigned/, flash[:notice])
    assert_equal new_category, transaction.reload.dest_account
  end

  test "should apply retroactively after updating a rule when flagged" do
    bank = accounts(:linked_asset)
    old_category = Account.create!(user: @user, currency: currencies(:usd), name: "Old Cat 2", kind: :expense)
    target = @import_rule.account
    source = Simplefin::Transaction.create!(
      account: simplefin_accounts(:linked_one), remote_id: "ctrl_update_apply",
      amount: "-3.00", description: "UPDATEAPPLY ITEM", transacted_at: 1.day.ago, posted: 1.day.ago
    )
    transaction = create_sourced_transaction(
      user: @user, src_account: bank, dest_account: old_category, amount_minor: 300,
      currency: currencies(:usd), description: "UPDATEAPPLY ITEM", transacted_at: 1.day.ago, sourceable: source
    )

    patch import_rule_url(@import_rule), params: {
      apply_after_save: "1", import_rule: { match_pattern: "UPDATEAPPLY" }
    }

    assert_match(/reassigned/, flash[:notice])
    assert_equal target, transaction.reload.dest_account
  end

  private

    def current_user_top_priority
      @user.import_rules.maximum(:priority) || -1
    end
end
