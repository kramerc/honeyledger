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

    # Fixture: 2500.00 reported balance and a single -75.00 row.
    result = @linked_lunchflow_account.suggested_opening_balance

    assert_equal 2575.to_d, result[:amount]
  end

  test "suggested_opening_balance walks back a negative inbound transfer as money arriving" do
    lunchflow_account = build_lunchflow_account(balance: "100.00")
    build_lunchflow_transaction(lunchflow_account, amount: "-30.00", merchant: "Test Merchant")
    build_lunchflow_transaction(lunchflow_account, amount: "-20.00", merchant: "TRANSFERRED FROM Test Savings")

    # 100.00 - (-30.00 + 20.00). Subtracting the raw feed signs would return 150.00.
    assert_equal 110.to_d, lunchflow_account.suggested_opening_balance[:amount]
  end

  test "suggested_opening_balance reads the direction from the resolved description" do
    lunchflow_account = build_lunchflow_account(balance: "100.00")
    # The merchant wins over the description, exactly as the importer resolves it, so
    # the transfer wording here is not what decides the direction.
    build_lunchflow_transaction(
      lunchflow_account,
      amount: "-20.00",
      merchant: "Test Merchant",
      description: "TRANSFERRED FROM Test Savings"
    )

    assert_equal 120.to_d, lunchflow_account.suggested_opening_balance[:amount]
  end

  test "creating an account_source enqueues an import" do
    account = accounts(:one)

    assert_enqueued_with(job: Lunchflow::ImportTransactionsJob, args: [ { lunchflow_account_id: @unlinked_lunchflow_account.id } ]) do
      AccountSource.create!(account: account, sourceable: @unlinked_lunchflow_account)
    end
  end

  private

    # Built here rather than added to the fixtures: test/system/integrations_test.rb
    # asserts the exact list of fixture account names on the integrations page.
    def build_lunchflow_account(balance:)
      Lunchflow::Account.create!(
        connection: lunchflow_connections(:one),
        remote_id: "opening_balance_#{balance}",
        institution_name: "Test Bank",
        name: "Test Checking",
        provider: "finicity",
        status: "ACTIVE",
        currency: "USD",
        balance: balance
      )
    end

    def build_lunchflow_transaction(lunchflow_account, amount:, merchant:, description: "Test Transaction")
      lunchflow_account.transactions.create!(
        remote_id: "opening_balance_txn_#{merchant}",
        amount: amount,
        currency: "USD",
        description: description,
        merchant: merchant,
        date: 1.day.ago.to_date,
        pending: false
      )
    end
end
