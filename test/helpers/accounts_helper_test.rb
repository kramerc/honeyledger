require "test_helper"

class AccountsHelperTest < ActionView::TestCase
  include ERB::Util

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
