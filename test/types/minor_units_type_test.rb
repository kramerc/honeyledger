require "test_helper"

class MinorUnitsTypeTest < ActiveSupport::TestCase
  setup do
    @type = MinorUnitsType.new
  end

  test "parses a long integer string whole" do
    assert_equal 123_456_789_012_345_678_901_234_567_890, @type.cast("123456789012345678901234567890")
  end

  test "parses signed and padded strings" do
    assert_equal(-10**21, @type.cast(" -1000000000000000000000 "))
    assert_equal 42, @type.cast("+42")
  end

  test "casts BigDecimal and Integer values exactly" do
    assert_equal 10**21, @type.cast(BigDecimal("1e21"))
    assert_equal 10**77, @type.cast(10**77)
  end

  test "casts nil and blank to nil" do
    assert_nil @type.cast(nil)
    assert_nil @type.cast("")
  end

  test "rejects strings that are not plain integers" do
    assert_nil @type.cast("abc")
    assert_nil @type.cast("1e21")
    assert_nil @type.cast("1.5")
  end

  test "rejects strings longer than the cap" do
    assert_equal(-(10**78 - 1), @type.cast("-" + "9" * 78))
    assert_nil @type.cast("9" * (MinorUnitsType::MAX_STRING_LENGTH + 1))
  end
end
