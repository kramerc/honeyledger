require "test_helper"

class ImportRulesHelperTest < ActionView::TestCase
  test "highlight_match wraps the matched span for each match type" do
    assert_equal %(BLUE <mark class="ir-mark">COFF</mark>EE), highlight_match("BLUE COFFEE", "coff", "contains")
    assert_equal %(<mark class="ir-mark">BLUE</mark> COFFEE), highlight_match("BLUE COFFEE", "blue", "starts_with")
    assert_equal %(BLUE <mark class="ir-mark">COFFEE</mark>), highlight_match("BLUE COFFEE", "coffee", "ends_with")
    assert_equal %(<mark class="ir-mark">BLUE COFFEE</mark>), highlight_match("BLUE COFFEE", "blue coffee", "exact")
  end

  test "highlight_match returns the description unchanged when nothing matches" do
    assert_equal "BLUE COFFEE", highlight_match("BLUE COFFEE", "xyz", "contains")
    assert_equal "BLUE COFFEE", highlight_match("BLUE COFFEE", "blue", "exact")
    assert_equal "BLUE COFFEE", highlight_match("BLUE COFFEE", "", "contains")
  end

  test "match-type labels" do
    assert_equal "Starts", match_type_short_label("starts_with")
    assert_equal "starts with", match_type_phrase("starts_with")
  end
end
