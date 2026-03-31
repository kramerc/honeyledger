require "test_helper"

class Lunchflow::AccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @linked_lunchflow_account = lunchflow_accounts(:linked_one)
    @unlinked_lunchflow_account = lunchflow_accounts(:unlinked_one)
  end

  test "linked? returns true when ledger_account is present" do
    assert @linked_lunchflow_account.linked?
  end

  test "linked? returns false when ledger_account is nil" do
    assert_not @unlinked_lunchflow_account.linked?
  end

  test "unlinked? returns true when ledger_account is nil" do
    assert @unlinked_lunchflow_account.unlinked?
  end

  test "unlinked? returns false when ledger_account is present" do
    assert_not @linked_lunchflow_account.unlinked?
  end

  test "ledger_currency returns nil if app currency is not found" do
    lf_account = Lunchflow::Account.new(currency: "unknown")

    assert_nil lf_account.ledger_currency
  end

  test "ledger_currency returns app currency if unlinked" do
    assert_equal currencies(:usd), @unlinked_lunchflow_account.ledger_currency
  end

  test "ledger_currency returns app currency from ledger_account when linked" do
    @linked_lunchflow_account.currency = nil

    assert_not_nil @linked_lunchflow_account.ledger_account
    assert_equal currencies(:usd), @linked_lunchflow_account.ledger_currency
  end

  test "suggested_opening_balance returns nil if no app currency" do
    lf_account = Lunchflow::Account.new(currency: "invalid")

    assert_nil lf_account.suggested_opening_balance
  end

  test "suggested_opening_balance amount aligns with Lunch Flow transactions" do
    assert_not_empty @linked_lunchflow_account.transactions

    amount_sum = @linked_lunchflow_account.transactions.reduce(0.to_d) do |sum, transaction|
      sum + transaction.amount.to_d
    end
    result = @linked_lunchflow_account.suggested_opening_balance

    expected_amount = @linked_lunchflow_account.balance.to_d - amount_sum
    assert_equal expected_amount, result[:amount]
  end

  test "after_update callback on Account enqueues import when sourceable changes" do
    account = accounts(:one)

    assert_enqueued_with(job: Lunchflow::ImportTransactionsJob, args: [ { lunchflow_account_id: @unlinked_lunchflow_account.id } ]) do
      account.update!(sourceable: @unlinked_lunchflow_account)
    end
  end
end
