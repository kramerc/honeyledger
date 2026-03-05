require "test_helper"

class MinorableTest < ActiveSupport::TestCase
  class TestModel
    include ActiveModel::Model
    include ActiveModel::Callbacks
    include ActiveModel::Validations
    include Minorable

    define_model_callbacks :save, only: :before

    attr_accessor :currency, :fx_currency

    attr_accessor :decimal_amount, :decimal_fx_amount, :decimal_nested_amount
    minorable :decimal_amount
    minorable :decimal_fx_amount, with: :fx_currency
    minorable :decimal_nested_amount, with: "nested.currency"

    attr_accessor :amount_minor, :fx_amount_minor, :nested_amount_minor
    unminorable :amount_minor
    unminorable :fx_amount_minor, with: :fx_currency
    unminorable :nested_amount_minor, with: "nested.currency"
    validates_presence_of :amount, :nested_amount

    def save
      run_callbacks :save do
        # no op
      end
    end

    def nested
      self
    end
  end

  # Stub of Transaction model to explicitly test Minorable with ActiveRecord
  class Transaction < ApplicationRecord
    include Minorable
    unminorable :amount_minor

    belongs_to :currency
  end

  setup do
    @test_model = TestModel.new(
      currency: currencies(:usd), # 2 decimal places
      fx_currency: currencies(:btc), # 8 decimal places
      decimal_amount: "50.00",
      decimal_fx_amount: "0.12345678",
      decimal_nested_amount: "123.45",
      amount_minor: 7000,
      fx_amount_minor: 876543210,
      nested_amount_minor: 54321
    )
  end

  test "minorable decimal_amount returns correct minor value" do
    assert_equal 5000, @test_model.decimal_amount_minor
  end

  test "minorable decimal_fx_amount returns correct minor value" do
    assert_equal 12345678, @test_model.decimal_fx_amount_minor
  end

  test "minorable decimal_nested_amount returns correct minor value" do
    assert_equal 12345, @test_model.decimal_nested_amount_minor
  end

  test "minorable handles zero decimal places" do
    @test_model.currency = currencies(:jpy)
    @test_model.decimal_amount = 100

    assert_equal 100, @test_model.decimal_amount_minor
  end

  test "minorable handles nil values" do
    @test_model.decimal_amount = nil

    assert_nil @test_model.decimal_amount_minor
  end

  test "minorable handles rounding to the nearest minor unit" do
    @test_model.decimal_amount = "12.345"

    assert_equal 1235, @test_model.decimal_amount_minor
  end

  test "unminorable amount_minor returns correct decimal value" do
    assert_equal BigDecimal(70.00), @test_model.amount
  end

  test "unminorable amount_minor= updates amount" do
    @test_model.amount = "19.95"
    assert_equal "19.95", @test_model.amount

    @test_model.amount_minor = 12345
    assert_equal BigDecimal(123.45), @test_model.amount
  end

  test "unminorable amount= sets amount" do
    @test_model.amount = "100.00"

    assert_equal "100.00", @test_model.amount
  end

  test "unminorable amount= does not immediately update amount_minor" do
    @test_model.amount = "100.00"

    assert_equal 7000, @test_model.amount_minor
  end

  test "unminorable amount= updates amount_minor on save" do
    @test_model.amount = "100.00"

    @test_model.save

    assert_equal 10000, @test_model.amount_minor
  end

  test "unminorable amount= has amount_written? return true" do
    @test_model.amount = "100.00"

    assert @test_model.amount_written?
  end

  test "unminorable amount_written? is false if not written" do
    assert_not @test_model.amount_written?
  end

  test "unminorable amount_written? is false after save" do
    @test_model.amount = "100.00"

    @test_model.save

    assert_not @test_model.amount_written?
  end

  test "unminorable sets nil on amount_minor if amount has changed" do
    @test_model.amount = nil

    @test_model.save

    assert_nil @test_model.amount_minor
  end

  test "unminorable does not set nil on amount_minor if amount is not changed" do
    @test_model.save

    assert_not_nil @test_model.amount_minor
  end

  test "resource is invalid if unminorable amount is nil" do
    @test_model.amount = nil

    assert_not @test_model.valid?
    assert_includes @test_model.errors[:amount], "can't be blank"
  end

  test "resource is invalid if unminorable amount is blank" do
    @test_model.amount = ""

    assert_not @test_model.valid?
    assert_includes @test_model.errors[:amount], "can't be blank"
  end

  test "resource is valid if unminorable amount is a float" do
    @test_model.amount = 123.45

    assert @test_model.valid?
  end

  test "resource is valid if unminorable amount is a BigDecimal" do
    @test_model.amount = BigDecimal(123.45)

    assert @test_model.valid?
  end

  test "resource is valid if unminorable amount is a numeric string" do
    @test_model.amount = "123.45"

    assert @test_model.valid?
  end

  test "resource is valid if unminorable amount is an integer" do
    @test_model.amount = 12345

    assert @test_model.valid?
  end

  test "resource is invalid if unminorable amount is not numeric" do
    @test_model.amount = "invalid"

    assert @test_model.invalid?
    assert_includes @test_model.errors[:amount], "is not a number"
  end

  test "resource is invalid if unminorable amount is changed without a currency" do
    @test_model.amount = "100.00"
    @test_model.currency = nil

    assert @test_model.invalid?
    assert_includes @test_model.errors[:amount], "cannot be saved without currency present"
  end

  test "resource is not saved if unminorable amount is changed without a currency" do
    @test_model.amount = "100.00"
    @test_model.currency = nil

    assert_not @test_model.save
  end

  test "unminorable fx_amount_minor returns correct decimal value" do
    assert_equal BigDecimal(8.76543210), @test_model.fx_amount
  end

  test "unminorable fx_amount_minor= updates fx_amount" do
    @test_model.fx_amount = "8.935"
    assert_equal "8.935", @test_model.fx_amount

    @test_model.fx_amount_minor = 123456789
    assert_equal BigDecimal(1.23456789), @test_model.fx_amount
  end

  test "unminorable fx_amount= sets fx_amount" do
    @test_model.fx_amount = "100.00"

    assert_equal "100.00", @test_model.fx_amount
  end

  test "unminorable fx_amount= does not immediately update fx_amount_minor" do
    @test_model.fx_amount = "100.00"

    assert_equal 876543210, @test_model.fx_amount_minor
  end

  test "unminorable fx_amount= updates fx_amount_minor on save" do
    @test_model.fx_amount = "2.12345678"

    @test_model.save

    assert_equal 212345678, @test_model.fx_amount_minor
  end

  test "unminorable fx_amount= has fx_amount_written? return true" do
    @test_model.fx_amount = "100.00"

    assert @test_model.fx_amount_written?
  end

  test "unminorable fx_amount_written? is false if not written" do
    assert_not @test_model.fx_amount_written?
  end

  test "unminorable fx_amount_written? is false after save" do
    @test_model.fx_amount = "100.00"

    @test_model.save

    assert_not @test_model.fx_amount_written?
  end

  test "unminorable sets nil on fx_amount_minor if fx_amount has changed" do
    @test_model.fx_amount = nil

    @test_model.save

    assert_nil @test_model.fx_amount_minor
  end

  test "unminorable does not set nil on fx_amount_minor if fx_amount is not changed" do
    @test_model.save

    assert_not_nil @test_model.fx_amount_minor
  end

  test "resource is valid if unminorable fx_amount is nil" do
    @test_model.fx_amount = nil

    assert @test_model.valid?
  end

  test "resource is valid if unminorable fx_amount is blank" do
    @test_model.fx_amount = ""

    assert @test_model.valid?
  end

  test "resource is valid if unminorable fx_amount is a float" do
    @test_model.fx_amount = 123.45

    assert @test_model.valid?
  end

  test "resource is valid if unminorable fx_amount is a BigDecimal" do
    @test_model.fx_amount = BigDecimal(123.45)

    assert @test_model.valid?
  end

  test "resource is valid if unminorable fx_amount is a numeric string" do
    @test_model.fx_amount = "123.45"

    assert @test_model.valid?
  end

  test "resource is valid if unminorable fx_amount is an integer" do
    @test_model.fx_amount = 12345

    assert @test_model.valid?
  end

  test "resource is invalid if unminorable fx_amount is not numeric" do
    @test_model.fx_amount = "invalid"

    assert @test_model.invalid?
    assert_includes @test_model.errors[:fx_amount], "is not a number"
  end

  test "resource is invalid if unminorable fx_amount is changed without a currency" do
    @test_model.fx_amount = "2.12345678"
    @test_model.fx_currency = nil

    assert @test_model.invalid?
    assert_includes @test_model.errors[:fx_amount], "cannot be saved without fx currency present"
  end

  test "resource is not saved if unminorable fx_amount is changed without a currency" do
    @test_model.fx_amount = "100.00"
    @test_model.fx_currency = nil

    assert_not @test_model.save
  end

  test "unminorable nested_amount_minor returns correct decimal value" do
    assert_equal BigDecimal(543.21), @test_model.nested_amount
  end

  test "unminorable nested_amount_minor= updates nested_amount" do
    @test_model.nested_amount = "19.95"
    assert_equal "19.95", @test_model.nested_amount

    @test_model.nested_amount_minor = 12345
    assert_equal BigDecimal(123.45), @test_model.nested_amount
  end

  test "unminorable nested_amount= sets nested_amount" do
    @test_model.nested_amount = "100.00"

    assert_equal "100.00", @test_model.nested_amount
  end

  test "unminorable nested_amount= does not immediately update nested_amount_minor" do
    @test_model.nested_amount = "100.00"

    assert_equal 54321, @test_model.nested_amount_minor
  end

  test "unminorable nested_amount= updates fx_amount_minor on save" do
    @test_model.nested_amount = "100.00"

    @test_model.save

    assert_equal 10000, @test_model.nested_amount_minor
  end

  test "unminorable nested_amount= has nested_amount_written? return true" do
    @test_model.nested_amount = "100.00"

    assert @test_model.nested_amount_written?
  end

  test "unminorable nested_amount_written? is false if not written" do
    assert_not @test_model.nested_amount_written?
  end

  test "unminorable nested_amount_written? is false after save" do
    @test_model.nested_amount = "100.00"

    @test_model.save

    assert_not @test_model.nested_amount_written?
  end

  test "unminorable sets nil on nested_amount_minor if nested_amount has changed" do
    @test_model.nested_amount = nil

    @test_model.save

    assert_nil @test_model.nested_amount_minor
  end

  test "unminorable does not set nil on nested_amount_minor if nested_amount is not changed" do
    @test_model.save

    assert_not_nil @test_model.nested_amount_minor
  end

  test "resource is invalid if unminorable nested_amount is nil" do
    @test_model.nested_amount = nil

    assert_not @test_model.valid?
    assert_includes @test_model.errors[:nested_amount], "can't be blank"
  end

  test "resource is invalid if unminorable nested_amount is blank" do
    @test_model.nested_amount = ""

    assert_not @test_model.valid?
    assert_includes @test_model.errors[:nested_amount], "can't be blank"
  end

  test "resource is valid if unminorable nested_amount is a float" do
    @test_model.nested_amount = 123.45

    assert @test_model.valid?
  end

  test "resource is valid if unminorable nested_amount is a BigDecimal" do
    @test_model.nested_amount = BigDecimal(123.45)

    assert @test_model.valid?
  end

  test "resource is valid if unminorable nested_amount is a numeric string" do
    @test_model.nested_amount = "123.45"

    assert @test_model.valid?
  end

  test "resource is valid if unminorable nested_amount is an integer" do
    @test_model.nested_amount = 12345

    assert @test_model.valid?
  end

  test "resource is invalid if unminorable nested_amount is not numeric" do
    @test_model.nested_amount = "invalid"

    assert @test_model.invalid?
    assert_includes @test_model.errors[:nested_amount], "is not a number"
  end

  test "resource is invalid if unminorable nested_amount is changed without a currency" do
    @test_model.nested_amount = 100.00
    @test_model.currency = nil # alias of nested.currency

    assert @test_model.invalid?
    assert_includes @test_model.errors[:nested_amount], "cannot be saved without nested.currency present"
  end

  test "resource is not saved if unminorable nested_amount is changed without a currency" do
    @test_model.nested_amount = "100.00"
    @test_model.currency = nil # alias of nested.currency

    assert_not @test_model.save
  end

  test "unminorable handles rounding to the nearest minor unit" do
    @test_model.amount = "12.345"

    @test_model.save

    assert_equal 1235, @test_model.amount_minor
  end

  test "unminorable handles zero decimal places" do
    @test_model.currency = currencies(:jpy)
    @test_model.amount = 100

    @test_model.save

    assert_equal 100, @test_model.amount_minor
  end

  test "unminorable minor writer handles minor attribute from ActiveRecord" do
    transaction = Transaction.new(currency: currencies(:usd), amount_minor: 5000)
    assert_equal BigDecimal(50.00), transaction.amount

    transaction.amount = "100.00"
    assert_equal "100.00", transaction.amount

    transaction.amount_minor = 7500

    assert_equal BigDecimal(75.00), transaction.amount
    assert_equal 7500, transaction.amount_minor
  end
end
