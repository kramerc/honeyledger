require "test_helper"

class Simplefin::AccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @linked_simplefin_account = simplefin_accounts(:linked_one)
    @unlinked_simplefin_account = simplefin_accounts(:unlinked_one)
    @reconciled_simplefin_account = simplefin_accounts(:reconciled_one)
  end

  test "linked? returns true when account_id is present" do
    assert @linked_simplefin_account.linked?
  end

  test "linked? returns false when account_id is nil" do
    assert_not @unlinked_simplefin_account.linked?
  end

  test "unlinked? returns true when account_id is nil" do
    assert @unlinked_simplefin_account.unlinked?
  end

  test "unlinked? returns false when account_id is present" do
    assert_not @linked_simplefin_account.unlinked?
  end

  test "ledger_currency returns nil if app currency is not found" do
    simplefin_account = Simplefin::Account.new(currency: "unknown")

    assert_nil simplefin_account.ledger_currency
  end

  test "ledger_currency returns app currency if unlinked" do
    assert_equal currencies(:usd), @unlinked_simplefin_account.ledger_currency
  end

  test "ledger_currency returns app currency from ledger_account when linked" do
    @linked_simplefin_account.currency = nil

    assert_not_nil @linked_simplefin_account.ledger_account
    assert_equal currencies(:usd), @linked_simplefin_account.ledger_currency
  end

  test "ledger_currency returns app currency from record when unlinked" do
    assert_nil @unlinked_simplefin_account.ledger_account
    assert_equal currencies(:usd), @unlinked_simplefin_account.ledger_currency
  end

  test "build_opening_balance_ledger_transactions returns nil if no app currency" do
    simplefin_account = Simplefin::Account.new(currency: "invalid")
    transaction = simplefin_account.build_opening_balance_ledger_transaction

    assert_nil transaction
  end

  test "build_opening_balance_ledger_transactions amount aligns with SimpleFIN transactions" do
    assert_not_empty @reconciled_simplefin_account.transactions

    amount_sum = @reconciled_simplefin_account.transactions.reduce(0) do |sum, transaction|
      sum + transaction.amount_minor
    end
    transaction = @reconciled_simplefin_account.build_opening_balance_ledger_transaction

    expected_amount = @reconciled_simplefin_account.balance_minor - amount_sum
    assert_equal expected_amount, transaction.amount_minor
  end

  test "build_opening_balance_ledger_transactions date aligns with SimpleFIN transactions" do
    assert_not_empty @reconciled_simplefin_account.transactions

    oldest_date = @reconciled_simplefin_account.transactions.reduce(Time.current) do |date, transaction|
      [
        date,
        transaction.transacted_at,
        transaction.posted,
        transaction.created_at
      ].compact.min
    end
    transaction = @reconciled_simplefin_account.build_opening_balance_ledger_transaction

    assert_equal oldest_date.beginning_of_day, transaction.transacted_at
  end

  test "enqueue_import enqueues TransactionImportJob with correct account_id" do
    assert_enqueued_with(job: TransactionImportJob, args: [ { simplefin_account_id: @linked_simplefin_account.id } ]) do
      @linked_simplefin_account.enqueue_import
    end
  end

  test "after_update callback enqueues import when account_id changes" do
    account = accounts(:one)

    assert_enqueued_with(job: TransactionImportJob, args: [ { simplefin_account_id: @unlinked_simplefin_account.id } ]) do
      @unlinked_simplefin_account.update!(ledger_account: account)
    end
  end

  test "after_update callback does not enqueue import when account_id does not change" do
    assert_no_enqueued_jobs(only: TransactionImportJob) do
      @linked_simplefin_account.update!(name: "Updated Name")
    end
  end

  test "validates uniqueness of ledger_account_id" do
    duplicate = Simplefin::Account.new(
      connection: @linked_simplefin_account.connection,
      ledger_account: @linked_simplefin_account.ledger_account,
      remote_id: "duplicate_remote_id",
      name: "Duplicate",
      currency: "USD"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ledger_account_id], "has already been taken"
  end

  test "allows multiple accounts with nil ledger_account_id" do
    connection = simplefin_connections(:one)

    account1 = Simplefin::Account.create!(
      connection: connection,
      ledger_account: nil,
      remote_id: "remote_1",
      name: "Unlinked 1",
      currency: "USD"
    )

    account2 = Simplefin::Account.create!(
      connection: connection,
      ledger_account: nil,
      remote_id: "remote_2",
      name: "Unlinked 2",
      currency: "USD"
    )

    assert account1.valid?
    assert account2.valid?
  end
end
