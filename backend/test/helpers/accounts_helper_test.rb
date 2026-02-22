require "test_helper"

class AccountsHelperTest < ActionView::TestCase
  include ERB::Util

  test "account_options_with_kind includes data attributes" do
    accounts = [
      accounts(:asset_account),
      accounts(:expense_account)
    ]

    result = account_options_with_kind(accounts, accounts(:asset_account).id)

    assert_match(/data-kind="asset"/, result)
    assert_match(/data-currency="USD"/, result)
    assert_match(/selected/, result)
  end
end
