# Attribute type for minor-unit amount columns (`numeric(78, 0)`).
#
# Reads already arrive as exact Integers, but ActiveModel's integer types cut
# string input to 16 bytes before parsing, so a large amount submitted as a
# form param would be silently truncated. This type parses the whole string,
# accepting only plain integers up to MAX_STRING_LENGTH characters; anything
# else casts to nil. Models validate user-supplied values against RANGE (with
# `only_integer`), so rejected input fails validation instead of reaching the
# database as nil or as an overflowing value.
class MinorUnitsType < ActiveModel::Type::BigInteger
  DIGITS = 78
  RANGE = (-(10**DIGITS) + 1)..(10**DIGITS - 1)
  MAX_STRING_LENGTH = DIGITS + 1 # room for a sign
  INTEGER_PATTERN = /\A[+-]?\d+\z/

  private
    def cast_value(value)
      return super unless value.is_a?(::String)

      string = value.strip
      return nil if string.length > MAX_STRING_LENGTH || !INTEGER_PATTERN.match?(string)

      string.to_i
    end
end
