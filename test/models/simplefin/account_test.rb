require "test_helper"

class Simplefin::AccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @linked_simplefin_account = simplefin_accounts(:linked_one)
    @unlinked_simplefin_account = simplefin_accounts(:unlinked_one)
    @reconciled_simplefin_account = simplefin_accounts(:reconciled_one)
  end

  test "linked? returns true when ledger_account is present" do
    assert @linked_simplefin_account.linked?
  end

  test "linked? returns false when ledger_account is nil" do
    assert_not @unlinked_simplefin_account.linked?
  end

  test "unlinked? returns true when ledger_account is nil" do
    assert @unlinked_simplefin_account.unlinked?
  end

  test "unlinked? returns false when ledger_account is present" do
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

  test "suggested_opening_balance returns nil if no app currency" do
    simplefin_account = Simplefin::Account.new(currency: "invalid")

    assert_nil simplefin_account.suggested_opening_balance
  end

  test "suggested_opening_balance amount aligns with SimpleFIN transactions" do
    assert_not_empty @reconciled_simplefin_account.transactions

    amount_sum = @reconciled_simplefin_account.transactions.reduce(0.to_d) do |sum, transaction|
      sum + transaction.amount.to_d
    end
    result = @reconciled_simplefin_account.suggested_opening_balance

    expected_amount = @reconciled_simplefin_account.balance.to_d - amount_sum
    assert_equal expected_amount, result[:amount]
  end

  test "suggested_opening_balance date aligns with SimpleFIN transactions" do
    assert_not_empty @reconciled_simplefin_account.transactions

    oldest_date = @reconciled_simplefin_account.transactions.reduce(Time.current) do |date, transaction|
      [
        date,
        transaction.transacted_at,
        transaction.posted,
        transaction.created_at
      ].compact.min
    end
    result = @reconciled_simplefin_account.suggested_opening_balance

    assert_equal oldest_date.beginning_of_day, result[:transacted_at]
  end

  test "after_update callback on Account enqueues import when sourceable changes" do
    account = accounts(:one)

    assert_enqueued_with(job: Simplefin::ImportTransactionsJob, args: [ { simplefin_account_id: @unlinked_simplefin_account.id } ]) do
      account.update!(sourceable: @unlinked_simplefin_account)
    end
  end

  test "after_update callback on Account does not enqueue import when sourceable does not change" do
    linked_account = accounts(:linked_asset)

    assert_no_enqueued_jobs(only: Simplefin::ImportTransactionsJob) do
      linked_account.update!(name: "Updated Name")
    end
  end
end
