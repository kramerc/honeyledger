require "test_helper"

class SimplefinTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)  # USD with 2 decimal places

    @bank_account = Account.create!(
      user: @user,
      currency: @currency,
      name: "Test Bank Account",
      kind: :asset
    )

    @simplefin_connection = simplefin_connections(:one)

    @simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: @bank_account,
      remote_id: "acc_test",
      name: "Test Account",
      currency: "USD",
      balance: "1000.00"
    )
  end

  test "amount_minor converts decimal amount based on currency decimal places" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_1",
      amount: "123.45",
      description: "Test Transaction",
      transacted_at: Time.current,
      pending: false
    )

    # 123.45 with 2 decimal places = 12345
    assert_equal 12345, transaction.amount_minor
  end

  test "amount_minor handles negative amounts" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_2",
      amount: "-50.00",
      description: "Expense",
      transacted_at: Time.current,
      pending: false
    )

    # -50.00 with 2 decimal places = -5000
    assert_equal(-5000, transaction.amount_minor)
  end

  test "amount_minor handles zero amount" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_3",
      amount: "0.00",
      description: "Zero Amount",
      transacted_at: Time.current,
      pending: false
    )

    assert_equal 0, transaction.amount_minor
  end

  test "amount_minor handles amounts with different decimal places" do
    # Use a currency with 0 decimal places (like JPY)
    currency_jpy = currencies(:jpy)

    jpy_account = Account.create!(
      user: @user,
      currency: currency_jpy,
      name: "JPY Account",
      kind: :asset
    )

    jpy_simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: jpy_account,
      remote_id: "acc_jpy",
      name: "JPY Account",
      currency: "JPY",
      balance: "10000"
    )

    transaction = SimplefinTransaction.create!(
      simplefin_account: jpy_simplefin_account,
      remote_id: "txn_jpy",
      amount: "5000",
      description: "JPY Transaction",
      transacted_at: Time.current,
      pending: false
    )

    # 5000 with 0 decimal places = 5000
    assert_equal 5000, transaction.amount_minor
  end

  test "amount_minor handles fractional cents properly" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_4",
      amount: "12.346",
      description: "Fractional Cents",
      transacted_at: Time.current,
      pending: false
    )

    # 12.346 with 2 decimal places = 1234 (truncated to integer)
    assert_equal 1234, transaction.amount_minor
  end

  test "amount_minor handles large amounts" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_5",
      amount: "999999.99",
      description: "Large Amount",
      transacted_at: Time.current,
      pending: false
    )

    # 999999.99 with 2 decimal places = 99999999
    assert_equal 99999999, transaction.amount_minor
  end

  test "amount_minor handles very small amounts" do
    transaction = SimplefinTransaction.create!(
      simplefin_account: @simplefin_account,
      remote_id: "txn_6",
      amount: "0.01",
      description: "One Cent",
      transacted_at: Time.current,
      pending: false
    )

    # 0.01 with 2 decimal places = 1
    assert_equal 1, transaction.amount_minor
  end

  test "amount_minor with cryptocurrency (8 decimal places)" do
    # Use a cryptocurrency with 8 decimal places (like BTC)
    currency_btc = currencies(:btc)

    btc_account = Account.create!(
      user: @user,
      currency: currency_btc,
      name: "BTC Account",
      kind: :asset
    )

    btc_simplefin_account = SimplefinAccount.create!(
      simplefin_connection: @simplefin_connection,
      account: btc_account,
      remote_id: "acc_btc",
      name: "BTC Account",
      currency: "BTC",
      balance: "1.00000000"
    )

    transaction = SimplefinTransaction.create!(
      simplefin_account: btc_simplefin_account,
      remote_id: "txn_btc",
      amount: "0.00012345",
      description: "BTC Transaction",
      transacted_at: Time.current,
      pending: false
    )

    # 0.00012345 with 8 decimal places = 12345
    assert_equal 12345, transaction.amount_minor
  end
end
