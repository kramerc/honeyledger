require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @account = accounts(:one)
  end

  test "should get index" do
    get accounts_url

    assert_response :success
  end

  test "should get index for a user with no accounts" do
    empty_user = User.create!(email: "empty-index@example.com", password: "password123")
    sign_in empty_user

    get accounts_url

    assert_response :success
  end

  test "should get index as JSON" do
    get accounts_url(format: :json)

    assert_response :success
    names = JSON.parse(response.body).map { |account| account["name"] }
    assert_includes names, accounts(:asset_account).name
  end

  test "should get new" do
    get new_account_url

    assert_response :success
  end

  test "should get new with an unlinked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_response :success
  end

  test "should redirect on new with a SimpleFIN account but no connection" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    @user.simplefin_connection = nil
    @user.save!

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to new_simplefin_connection_url
    assert_equal "Cannot import SimpleFIN account without a connection.", flash[:alert]
  end

  test "should redirect on new with linked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:linked_one)

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account already linked to another account.", flash[:alert]
  end

  test "should redirect on new with a SimpleFIN account not found" do
    get new_account_url, params: { simplefin_account_id: "invalid" }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  test "should on new scope finding a SimpleFIN account to the current user" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    simplefin_account.update!(connection: simplefin_connections(:two)) # Has different user

    get new_account_url, params: { simplefin_account_id: simplefin_account.id }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  test "should create account without opening balance" do
    assert_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "New Account",
          kind: "asset",
          currency_id: @account.currency_id
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_nil Account.last.opening_balance_transaction
  end

  test "should create account with no opening balance if zero" do
    assert_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "New Account with Zero Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_amount: "0",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_nil Account.last.opening_balance_transaction
  end

  test "should create account with opening balance" do
    # Account + Opening Balance Account
    assert_difference("Account.count", 2) do
      post accounts_url, params: {
        account: {
          name: "New Account with Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_amount: "500.00",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    new_account = Account.last
    assert_redirected_to account_url(new_account)
    assert_equal 50000, new_account.opening_balance_transaction.amount_minor
  end

  test "should create linked to a SimpleFIN account when given" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    assert_difference("Account.count", 1) do
      post accounts_url, params: {
        account: {
          name: "New Account",
          kind: "asset",
          currency_id: @account.currency_id
        },
        simplefin_account_id: simplefin_account.id
      }
    end

    assert_redirected_to account_url(Account.last)
    assert_includes Account.last.account_sources.map(&:sourceable), simplefin_account
  end

  test "should not link a SimpleFIN account to a non-linkable kind" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    assert_no_difference([ "Account.count", "AccountSource.count" ]) do
      post accounts_url, params: {
        account: {
          name: "Groceries",
          kind: "expense",
          currency_id: @account.currency_id
        },
        simplefin_account_id: simplefin_account.id
      }
    end

    assert_response :unprocessable_entity
    assert_not simplefin_account.reload.linked?
  end

  test "rolls back account creation when AccountSource::Attach hits a concurrent-link race" do
    simplefin_account = simplefin_accounts(:unlinked_one)

    assert_no_difference("Account.count") do
      AccountSource::Attach.stub :call, ->(*) { raise AccountSource::Attach::MismatchedAccount, "race" } do
        post accounts_url, params: {
          account: { name: "Race Account", kind: "asset", currency_id: @account.currency_id },
          simplefin_account_id: simplefin_account.id
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "should redirect on create with a SimpleFIN account but no connection" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    @user.simplefin_connection = nil
    @user.save!

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to new_simplefin_connection_url
    assert_equal "Cannot import SimpleFIN account without a connection.", flash[:alert]
  end

  test "should redirect on create when given a linked SimpleFIN account" do
    simplefin_account = simplefin_accounts(:linked_one)

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account already linked to another account.", flash[:alert]
  end

  test "should redirect on create when given a SimpleFIN account not found" do
    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: "invalid"
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  test "should on create scope finding a SimpleFIN account to the current user" do
    simplefin_account = simplefin_accounts(:unlinked_one)
    simplefin_account.update!(connection: simplefin_connections(:two)) # Has different user

    post accounts_url, params: {
      account: {
        name: "New Account",
        kind: "asset",
        currency_id: @account.currency_id
      },
      simplefin_account_id: simplefin_account.id
    }

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN account to import was not found.", flash[:alert]
  end

  # Lunch Flow import tests

  test "should get new with an unlinked Lunch Flow account" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_response :success
  end

  test "should redirect on new with a Lunch Flow account but no connection" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    @user.lunchflow_connection = nil
    @user.save!

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to new_lunchflow_connection_url
    assert_equal "Cannot import Lunch Flow account without a connection.", flash[:alert]
  end

  test "should redirect on new with linked Lunch Flow account" do
    lunchflow_account = lunchflow_accounts(:linked_one)

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account already linked to another account.", flash[:alert]
  end

  test "should redirect on new with a Lunch Flow account not found" do
    get new_account_url, params: { lunchflow_account_id: "invalid" }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account to import was not found.", flash[:alert]
  end

  test "should on new scope finding a Lunch Flow account to the current user" do
    lunchflow_account = lunchflow_accounts(:unlinked_one)
    lunchflow_account.update!(connection: lunchflow_connections(:two))

    get new_account_url, params: { lunchflow_account_id: lunchflow_account.id }

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow account to import was not found.", flash[:alert]
  end

  test "should validate on create" do
    assert_no_difference("Account.count") do
      post accounts_url, params: {
        account: {
          name: "",
          kind: "asset",
          currency_id: @account.currency_id
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should show account" do
    get account_url(@account)
    assert_response :success
  end

  test "should get edit" do
    get edit_account_url(@account)
    assert_response :success
  end

  test "should update account without opening balance" do
    patch account_url(@account), params: {
      account: {
        name: "Updated Name",
        kind: @account.kind,
        currency_id: @account.currency_id
      }
    }
    assert_redirected_to account_url(@account)

    @account.reload
    assert_equal "Updated Name", @account.name
  end

  test "should update account with positive opening balance" do
    patch account_url(@account), params: {
      account: {
        name: @account.name,
        kind: @account.kind,
        currency_id: @account.currency_id,
        opening_balance_amount: "100.00",
        opening_balance_transacted_at: Time.current
      }
    }
    assert_redirected_to account_url(@account)

    @account.reload
    assert_equal 10000, @account.opening_balance_transaction.amount_minor
  end

  test "should create account with negative opening balance" do
    # Account + Opening Balance Account
    assert_difference("Account.count", 2) do
      post accounts_url, params: {
        account: {
          name: "New Account with Balance",
          kind: "asset",
          currency_id: @account.currency_id,
          opening_balance_amount: "-500.00",
          opening_balance_transacted_at: Time.current
        }
      }
    end

    new_account = Account.last
    assert_redirected_to account_url(new_account)
    assert_equal 50000, new_account.opening_balance_transaction.amount_minor, "negative opening balance is persisted as absolute value"
    assert new_account.opening_balance_transaction.src_account.real?, "src_account should be the real account for a negative opening balance"
  end

  test "should validate on update" do
    assert_no_difference("Account.count") do
      patch account_url(@account), params: {
        account: {
          name: ""
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should destroy account" do
    unused_account = Account.create!(
      user: users(:one),
      name: "Unused Account",
      kind: "asset",
      currency: currencies(:usd)
    )
    assert_difference("Account.count", -1) do
      delete account_url(unused_account)
    end

    assert_redirected_to accounts_url
  end

  test "should not destroy account that still has transactions" do
    account = accounts(:asset_account) # referenced by transactions(:one)

    assert_no_difference("Account.count") do
      delete account_url(account)
    end

    assert_redirected_to accounts_url
    assert_equal "This account still has transactions, so it can't be deleted.", flash[:alert]
  end

  test "should respond unprocessable entity for JSON destroy of an account with transactions" do
    account = accounts(:asset_account)

    assert_no_difference("Account.count") do
      delete account_url(account), as: :json
    end

    assert_response :unprocessable_entity
    # restrict_with_error adds a :base error before halting, so the model's
    # errors are present in the JSON body.
    assert_includes JSON.parse(response.body).keys, "base"
  end

  test "should merge selected accounts into the chosen target" do
    target = Account.create!(user: @user, name: "Amazon", kind: :expense, currency: currencies(:usd))
    source = Account.create!(user: @user, name: "Amazon Marketplace", kind: :expense, currency: currencies(:usd))
    transaction = Transaction.create!(
      user: @user, src_account: accounts(:asset_account), dest_account: source,
      amount_minor: 800, currency: currencies(:usd), transacted_at: 1.day.ago
    )

    post merge_accounts_url, params: { account_ids: [ target.id, source.id ], target_account_id: target.id }

    assert_redirected_to accounts_url
    assert_equal "Accounts merged into Amazon.", flash[:notice]
    assert_nil Account.find_by(id: source.id)
    assert_equal target.id, transaction.reload.dest_account_id
  end

  test "should not merge accounts belonging to another user" do
    target = Account.create!(user: @user, name: "Amazon", kind: :expense, currency: currencies(:usd))
    other = Account.create!(user: users(:two), name: "Theirs", kind: :expense, currency: currencies(:usd))

    post merge_accounts_url, params: { account_ids: [ target.id, other.id ], target_account_id: target.id }

    # The other user's account is scoped out, leaving no real source to merge.
    assert_redirected_to accounts_url
    assert_equal "Select at least one other account to merge", flash[:alert]
    assert Account.exists?(other.id)
  end

  test "should not merge accounts of different kinds" do
    target = Account.create!(user: @user, name: "Foo", kind: :expense, currency: currencies(:usd))
    source = Account.create!(user: @user, name: "Bar", kind: :revenue, currency: currencies(:usd))

    post merge_accounts_url, params: { account_ids: [ target.id, source.id ], target_account_id: target.id }

    assert_redirected_to accounts_url
    assert_equal "Only expense or revenue accounts of the same kind can be merged", flash[:alert]
    assert Account.exists?(source.id)
  end

  test "should require a target account to merge" do
    source = Account.create!(user: @user, name: "Bar", kind: :expense, currency: currencies(:usd))

    post merge_accounts_url, params: { account_ids: [ source.id ] }

    assert_redirected_to accounts_url
    assert_equal "Pick a target account to keep.", flash[:alert]
    assert Account.exists?(source.id)
  end

  test "should clean up empty expense and revenue accounts" do
    empty_expense = Account.create!(user: @user, name: "Empty Expense", kind: :expense, currency: currencies(:usd))
    empty_revenue = Account.create!(user: @user, name: "Empty Revenue", kind: :revenue, currency: currencies(:usd))

    assert_difference("Account.count", -2) do
      delete cleanup_empty_accounts_url, params: { account_ids: [ empty_expense.id, empty_revenue.id ] }
    end

    assert_redirected_to accounts_url
    assert_equal "Deleted 2 empty accounts.", flash[:notice]
  end

  test "cleanup_empty keeps an account that still has transactions" do
    account = accounts(:expense_account) # dest of transactions(:one)

    assert_no_difference("Account.count") do
      delete cleanup_empty_accounts_url, params: { account_ids: [ account.id ] }
    end

    assert Account.exists?(account.id)
    assert_equal "No empty accounts to clean up.", flash[:notice]
  end

  test "cleanup_empty keeps a merge-reference account so its merge can be undone" do
    expense = Account.create!(user: @user, name: "Merge Reference Expense", kind: :expense, currency: currencies(:usd))
    revenue = Account.create!(user: @user, name: "Merge Reference Revenue", kind: :revenue, currency: currencies(:usd))
    withdrawal = Transaction.create!(
      user: @user, src_account: accounts(:asset_account), dest_account: expense,
      amount_minor: 750, currency: currencies(:usd), transacted_at: 1.day.ago
    )
    deposit = Transaction.create!(
      user: @user, src_account: revenue, dest_account: accounts(:linked_asset),
      amount_minor: 750, currency: currencies(:usd), transacted_at: 1.day.ago
    )
    merger = Transaction::Merge.new(withdrawal, deposit, user: @user)
    assert merger.call, "Merge setup failed: #{merger.errors.join(", ")}"

    # Both accounts now hold only their zeroed, merged-away originals, so cleanup must skip them.
    assert_no_difference("Account.count") do
      delete cleanup_empty_accounts_url, params: { account_ids: [ expense.id, revenue.id ] }
    end

    assert Account.exists?(expense.id)
    assert Account.exists?(revenue.id)
    assert Transaction::Unmerge.new(merger.merged_transaction, user: @user).call, "unmerge should still be possible"
  end

  test "cleanup_empty keeps an empty account that is an import-rule target" do
    rule_target = Account.create!(user: @user, name: "Coffee", kind: :expense, currency: currencies(:usd))
    rule = ImportRule.create!(user: @user, account: rule_target, match_pattern: "Coffee Shop", match_type: :contains, priority: 0)

    assert_no_difference("Account.count") do
      delete cleanup_empty_accounts_url, params: { account_ids: [ rule_target.id ] }
    end

    assert Account.exists?(rule_target.id), "an import-rule target must not be cleaned up"
    assert ImportRule.exists?(rule.id), "its import rule mapping must survive"
  end

  test "cleanup_empty ignores accounts belonging to another user" do
    other = Account.create!(user: users(:two), name: "Theirs", kind: :expense, currency: currencies(:usd))

    assert_no_difference("Account.count") do
      delete cleanup_empty_accounts_url, params: { account_ids: [ other.id ] }
    end

    assert Account.exists?(other.id)
  end

  test "cleanup_empty ignores asset and liability accounts" do
    asset = Account.create!(user: @user, name: "Empty Asset", kind: :asset, currency: currencies(:usd))

    assert_no_difference("Account.count") do
      delete cleanup_empty_accounts_url, params: { account_ids: [ asset.id ] }
    end

    assert Account.exists?(asset.id)
  end

  test "cleanup_empty deletes only the empty accounts when given a mix" do
    empty_expense = Account.create!(user: @user, name: "Empty Expense", kind: :expense, currency: currencies(:usd))
    non_empty = accounts(:expense_account) # dest of transactions(:one)

    assert_difference("Account.count", -1) do
      delete cleanup_empty_accounts_url, params: { account_ids: [ empty_expense.id, non_empty.id ] }
    end

    assert_not Account.exists?(empty_expense.id)
    assert Account.exists?(non_empty.id)
    assert_equal "Deleted 1 empty account.", flash[:notice]
  end

  test "cleanup_empty reports nothing to clean up when no ids match" do
    delete cleanup_empty_accounts_url, params: { account_ids: [] }

    assert_redirected_to accounts_url
    assert_equal "No empty accounts to clean up.", flash[:notice]
  end
end
