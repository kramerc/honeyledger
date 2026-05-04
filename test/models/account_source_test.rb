require "test_helper"

class AccountSourceTest < ActiveSupport::TestCase
  test "fixture rows match the expected aggregator account" do
    legacy = accounts(:linked_asset)
    join = legacy.account_sources.first

    assert_not_nil join
    assert_equal simplefin_accounts(:linked_one), join.sourceable
  end

  test "DB unique index on (sourceable_type, sourceable_id) blocks a second row" do
    simplefin_account = simplefin_accounts(:linked_one)

    assert_raises(ActiveRecord::RecordNotUnique) do
      AccountSource.create!(
        account: accounts(:asset_account),
        sourceable: simplefin_account
      )
    end
  end

  test "can be queried via the through-association on aggregator account" do
    simplefin_account = simplefin_accounts(:linked_one)

    assert_includes simplefin_account.ledger_accounts, accounts(:linked_asset)
  end
end
