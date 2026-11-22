require "test_helper"

class Keccak256Test < ActiveSupport::TestCase
  # Ethereum's Keccak-256 (original padding), not NIST SHA3-256.
  test "matches the published digests" do
    assert_equal "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", Keccak256.hexdigest("")
    assert_equal "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45", Keccak256.hexdigest("abc")
  end

  test "pads correctly either side of the 136-byte rate" do
    assert_equal "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446", Keccak256.hexdigest("a" * 135)
    assert_equal "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e", Keccak256.hexdigest("a" * 136)
    assert_equal "d869f639c7046b4929fc92a4d988a8b22c55fbadb802c0c66ebcd484f1915f39", Keccak256.hexdigest("a" * 137)
  end

  test "differs from SHA3-256" do
    assert_not_equal OpenSSL::Digest.new("SHA3-256").hexdigest("abc"), Keccak256.hexdigest("abc")
  end
end
