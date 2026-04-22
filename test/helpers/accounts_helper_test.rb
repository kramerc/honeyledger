require "test_helper"

class AccountsHelperTest < ActionView::TestCase
  include ERB::Util
  include ApplicationHelper
  include CurrenciesHelper

  # account_sidebar_link

  test "account_sidebar_link renders link to account transactions path" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account)

    assert_match account_transactions_path(account), result
  end

  test "account_sidebar_link includes account name" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account)

    assert_match account.name, result
  end

  test "account_sidebar_link gives the link a stable dom id for broadcast updates" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account)

    assert_match(/id="#{ActionView::RecordIdentifier.dom_id(account, :sidebar_link)}"/, result)
  end

  test "account_sidebar_link shows positive balance class for zero balance" do
    account = accounts(:asset_account)
    account.balance_minor = 0
    result = account_sidebar_link(account)

    assert_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_sidebar_link shows positive balance class for positive balance" do
    account = accounts(:asset_account)
    account.balance_minor = 1500
    result = account_sidebar_link(account)

    assert_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_sidebar_link shows negative balance class for negative balance" do
    account = accounts(:asset_account)
    account.balance_minor = -500
    result = account_sidebar_link(account)

    assert_match(/account__balance--negative/, result)
    assert_no_match(/account__balance--positive/, result)
  end

  test "account_sidebar_link omits balance when balance_minor is nil" do
    account = accounts(:asset_account)
    account.balance_minor = nil
    result = account_sidebar_link(account)

    assert_no_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_sidebar_link has active class on exact transactions path" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account, active_path: account_transactions_path(account))

    assert_match(/\bactive\b/, result)
  end

  test "account_sidebar_link has active class on sub-path of account" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account, active_path: "#{account_path(account)}/something")

    assert_match(/\bactive\b/, result)
  end

  test "account_sidebar_link has no active class on a different account path" do
    account = accounts(:asset_account)
    other = accounts(:liability_account)
    result = account_sidebar_link(account, active_path: account_transactions_path(other))

    assert_no_match(/\bactive\b/, result)
  end

  test "account_sidebar_link has no active class on unrelated path" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account, active_path: "/categories")

    assert_no_match(/\bactive\b/, result)
  end

  test "account_sidebar_link has no active class when active_path is nil (broadcast render)" do
    account = accounts(:asset_account)
    result = account_sidebar_link(account)

    assert_no_match(/\bactive\b/, result)
  end

  # account_options

  test "account_options returns collection" do
    accounts = [
      accounts(:one),
      accounts(:two)
    ]

    expected_options = [
      [ "Account One", accounts(:one).id, { data: {
        currency: accounts(:one).currency.code, kind: accounts(:one).kind
      } } ],
      [ "Account Two", accounts(:two).id, { data: {
        currency: accounts(:two).currency.code, kind: accounts(:two).kind
      } } ]
    ]
    assert_equal expected_options, account_options(accounts)
  end

  test "grouped_account_options_for_select returns grouped options with specified asset kinds" do
    accounts = [
      accounts(:one),
      accounts(:two)
    ]

    html = grouped_account_options_for_select(accounts, [ :asset ])

    expected_html = <<~HTML
      <optgroup label="Asset">
        <option data-currency="USD" data-kind="asset" value="#{accounts(:one).id}">Account One</option>
      </optgroup>
    HTML
    assert_dom_equal expected_html, html
  end
end
