require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "linkable scope returns only asset and liability accounts" do
    linkable = Account.linkable

    assert_includes linkable, accounts(:asset_account)
    assert_includes linkable, accounts(:liability_account)
    assert_includes linkable, accounts(:linked_asset)
    assert_includes linkable, accounts(:unlinked_liability)

    assert_not_includes linkable, accounts(:expense_account)
    assert_not_includes linkable, accounts(:revenue_account)
  end

  test "unlinked scope returns accounts without simplefin_account association" do
    unlinked = Account.unlinked

    assert_includes unlinked, accounts(:asset_account)
    assert_includes unlinked, accounts(:liability_account)
    assert_includes unlinked, accounts(:expense_account)
    assert_includes unlinked, accounts(:revenue_account)
    assert_includes unlinked, accounts(:unlinked_liability)

    assert_not_includes unlinked, accounts(:linked_asset)
  end

  test "linkable.unlinked chains scopes correctly" do
    linkable_unlinked = Account.linkable.unlinked

    assert_includes linkable_unlinked, accounts(:asset_account)
    assert_includes linkable_unlinked, accounts(:liability_account)
    assert_includes linkable_unlinked, accounts(:unlinked_liability)

    # Linked account should be excluded
    assert_not_includes linkable_unlinked, accounts(:linked_asset)

    # Non-linkable accounts should be excluded
    assert_not_includes linkable_unlinked, accounts(:expense_account)
    assert_not_includes linkable_unlinked, accounts(:revenue_account)
  end
end
