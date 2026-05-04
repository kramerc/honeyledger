require "test_helper"

class AccountSource::AttachTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:asset_account)
    @sourceable = Simplefin::Account.create!(
      connection: simplefin_connections(:one),
      remote_id: "attach_test_1",
      name: "Attach Test",
      currency: "USD",
      balance: "100.00"
    )
  end

  test "creates a join row when none exists" do
    assert_difference("AccountSource.count", 1) do
      AccountSource::Attach.call(account: @account, sourceable: @sourceable)
    end
  end

  test "is idempotent on the (sourceable_type, sourceable_id) key" do
    AccountSource::Attach.call(account: @account, sourceable: @sourceable)

    assert_no_difference("AccountSource.count") do
      AccountSource::Attach.call(account: @account, sourceable: @sourceable)
    end
  end

  test "raises if the same sourceable is already attached to a different ledger account" do
    AccountSource::Attach.call(account: @account, sourceable: @sourceable)

    other_account = accounts(:liability_account)

    assert_raises(AccountSource::Attach::MismatchedAccount) do
      AccountSource::Attach.call(account: other_account, sourceable: @sourceable)
    end
  end
end
