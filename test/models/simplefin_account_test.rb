require "test_helper"

class SimplefinAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @linked_account = simplefin_accounts(:linked_one)
    @unlinked_account = simplefin_accounts(:unlinked_one)
  end

  test "linked? returns true when account_id is present" do
    assert @linked_account.linked?
  end

  test "linked? returns false when account_id is nil" do
    assert_not @unlinked_account.linked?
  end

  test "unlinked? returns true when account_id is nil" do
    assert @unlinked_account.unlinked?
  end

  test "unlinked? returns false when account_id is present" do
    assert_not @linked_account.unlinked?
  end

  test "enqueue_import! enqueues TransactionImportJob with correct account_id" do
    assert_enqueued_with(job: TransactionImportJob, args: [ { simplefin_account_id: @linked_account.id } ]) do
      @linked_account.enqueue_import!
    end
  end

  test "after_update callback enqueues import when account_id changes" do
    account = accounts(:one)

    assert_enqueued_with(job: TransactionImportJob, args: [ { simplefin_account_id: @unlinked_account.id } ]) do
      @unlinked_account.update!(account: account)
    end
  end

  test "after_update callback does not enqueue import when account_id does not change" do
    assert_no_enqueued_jobs(only: TransactionImportJob) do
      @linked_account.update!(name: "Updated Name")
    end
  end

  test "validates uniqueness of account_id" do
    duplicate = SimplefinAccount.new(
      simplefin_connection: @linked_account.simplefin_connection,
      account: @linked_account.account,
      remote_id: "duplicate_remote_id",
      name: "Duplicate",
      currency: "USD"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:account_id], "has already been taken"
  end

  test "allows multiple accounts with nil account_id" do
    connection = simplefin_connections(:one)

    account1 = SimplefinAccount.create!(
      simplefin_connection: connection,
      account: nil,
      remote_id: "remote_1",
      name: "Unlinked 1",
      currency: "USD"
    )

    account2 = SimplefinAccount.create!(
      simplefin_connection: connection,
      account: nil,
      remote_id: "remote_2",
      name: "Unlinked 2",
      currency: "USD"
    )

    assert account1.valid?
    assert account2.valid?
  end
end
