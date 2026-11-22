# Attribute type for minor-unit amount columns (`numeric(78, 0)`).
#
# Reads already arrive as exact Integers, but ActiveModel's integer types cut
# string input to 16 bytes before parsing, so a large amount submitted as a
# form param would be silently truncated. This type parses the whole string,
# accepting only plain integers up to MAX_STRING_LENGTH characters; anything
# else casts to nil.
class MinorUnitsType < ActiveModel::Type::BigInteger
  MAX_STRING_LENGTH = 80
  INTEGER_PATTERN = /\A[+-]?\d+\z/

  private
    def cast_value(value)
      return super unless value.is_a?(::String)

      string = value.strip
      return nil if string.length > MAX_STRING_LENGTH || !INTEGER_PATTERN.match?(string)

      string.to_i
    end
end
