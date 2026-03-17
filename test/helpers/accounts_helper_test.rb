require "test_helper"

class AccountsHelperTest < ActionView::TestCase
  include ERB::Util
  include ApplicationHelper
  include CurrenciesHelper

  # Provide a controllable request for helpers that call request.path
  def request
    @mock_request ||= ActionDispatch::TestRequest.create
  end

  def with_path(path)
    request.env["PATH_INFO"] = path
  end

  setup do
    with_path("/")
  end

  # account_nav_link_to

  test "account_nav_link_to renders link to account transactions path" do
    account = accounts(:asset_account)
    result = account_nav_link_to(account)

    assert_match account_transactions_path(account), result
  end

  test "account_nav_link_to includes account name" do
    account = accounts(:asset_account)
    result = account_nav_link_to(account)

    assert_match account.name, result
  end

  test "account_nav_link_to shows positive balance class for zero balance" do
    account = accounts(:asset_account)
    account.balance_minor = 0
    result = account_nav_link_to(account)

    assert_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_nav_link_to shows positive balance class for positive balance" do
    account = accounts(:asset_account)
    account.balance_minor = 1500
    result = account_nav_link_to(account)

    assert_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_nav_link_to shows negative balance class for negative balance" do
    account = accounts(:asset_account)
    account.balance_minor = -500
    result = account_nav_link_to(account)

    assert_match(/account__balance--negative/, result)
    assert_no_match(/account__balance--positive/, result)
  end

  test "account_nav_link_to omits balance when balance_minor is nil" do
    account = accounts(:asset_account)
    account.balance_minor = nil
    result = account_nav_link_to(account)

    assert_no_match(/account__balance--positive/, result)
    assert_no_match(/account__balance--negative/, result)
  end

  test "account_nav_link_to has active class on exact transactions path" do
    account = accounts(:asset_account)
    with_path(account_transactions_path(account))
    result = account_nav_link_to(account)

    assert_match(/\bactive\b/, result)
  end

  test "account_nav_link_to has active class on sub-path of account" do
    account = accounts(:asset_account)
    with_path("#{account_path(account)}/something")
    result = account_nav_link_to(account)

    assert_match(/\bactive\b/, result)
  end

  test "account_nav_link_to has no active class on a different account path" do
    account = accounts(:asset_account)
    other = accounts(:liability_account)
    with_path(account_transactions_path(other))
    result = account_nav_link_to(account)

    assert_no_match(/\bactive\b/, result)
  end

  test "account_nav_link_to has no active class on unrelated path" do
    account = accounts(:asset_account)
    with_path("/categories")
    result = account_nav_link_to(account)

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
