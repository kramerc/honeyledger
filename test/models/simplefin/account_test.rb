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

  test "institution_name returns the org name" do
    account = Simplefin::Account.new(org: { "name" => "Test Bank" })

    assert_equal "Test Bank", account.institution_name
  end

  test "institution_name returns nil when org is absent" do
    account = Simplefin::Account.new(org: nil)

    assert_nil account.institution_name
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

    # Fixture: 50.00 reported balance, rows of -30.00, 25.00, 10.00 and 15.00 (net +20.00).
    result = @reconciled_simplefin_account.suggested_opening_balance

    assert_equal 30.to_d, result[:amount]
  end

  test "suggested_opening_balance walks back a negative inbound transfer as money arriving" do
    simplefin_account = build_simplefin_account(balance: "100.00")
    build_simplefin_transaction(simplefin_account, amount: "-30.00", description: "Test Purchase")
    build_simplefin_transaction(simplefin_account, amount: "-20.00", description: "TRANSFERRED FROM Test Savings")

    # The transfer is posted as +20.00 by the importer (#222), so the walk-back is
    # 100.00 - (-30.00 + 20.00). Subtracting the raw feed signs would return 150.00.
    assert_equal 110.to_d, simplefin_account.suggested_opening_balance[:amount]
  end

  test "suggested_opening_balance ignores a row the feed sent no amount for" do
    simplefin_account = build_simplefin_account(balance: "100.00")
    build_simplefin_transaction(simplefin_account, amount: "-30.00", description: "Test Purchase")
    build_simplefin_transaction(simplefin_account, amount: nil, description: "Test Transaction")

    assert_equal 130.to_d, simplefin_account.suggested_opening_balance[:amount]
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

  test "creating an account_source enqueues an import" do
    account = accounts(:one)

    assert_enqueued_with(job: Simplefin::ImportTransactionsJob, args: [ { simplefin_account_id: @unlinked_simplefin_account.id } ]) do
      AccountSource.create!(account: account, sourceable: @unlinked_simplefin_account)
    end
  end

  test "updating an account does not enqueue import when no source change" do
    linked_account = accounts(:linked_asset)

    assert_no_enqueued_jobs(only: Simplefin::ImportTransactionsJob) do
      linked_account.update!(name: "Updated Name")
    end
  end

  private

    # Built here rather than added to the fixtures: test/system/integrations_test.rb
    # asserts the exact list of fixture account names on the integrations page.
    def build_simplefin_account(balance:)
      Simplefin::Account.create!(
        connection: simplefin_connections(:one),
        remote_id: "opening_balance_#{balance}",
        org: { "name" => "Test Bank" },
        name: "Test Checking",
        currency: "USD",
        balance: balance,
        balance_date: Time.current
      )
    end

    def build_simplefin_transaction(simplefin_account, amount:, description:)
      simplefin_account.transactions.create!(
        remote_id: "opening_balance_txn_#{description}",
        amount: amount,
        description: description,
        posted: 1.day.ago,
        pending: false
      )
    end
end
