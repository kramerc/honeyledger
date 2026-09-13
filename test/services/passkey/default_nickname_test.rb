require "test_helper"

class Passkey::DefaultNicknameTest < ActiveSupport::TestCase
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36".freeze
  EDGE_WINDOWS = "#{CHROME_WINDOWS} Edg/129.0.0.0".freeze
  SAFARI_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze
  CHROME_ANDROID = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36".freeze
  FIREFOX_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:130.0) Gecko/20100101 Firefox/130.0".freeze

  test "names a known provider from its AAGUID regardless of the browser" do
    assert_equal "1Password", Passkey::DefaultNickname.call(aaguid: "BADA5566-A7AA-401F-BD96-45619A55120D", user_agent: CHROME_WINDOWS)
  end

  test "falls back to browser and platform from the user agent" do
    assert_equal "Chrome on Windows", Passkey::DefaultNickname.call(aaguid: "00000000-0000-0000-0000-000000000000", user_agent: CHROME_WINDOWS)
    assert_equal "Edge on Windows", Passkey::DefaultNickname.call(aaguid: nil, user_agent: EDGE_WINDOWS)
    assert_equal "Safari on iPhone", Passkey::DefaultNickname.call(aaguid: nil, user_agent: SAFARI_IPHONE)
    assert_equal "Chrome on Android", Passkey::DefaultNickname.call(aaguid: nil, user_agent: CHROME_ANDROID)
    assert_equal "Firefox on Mac", Passkey::DefaultNickname.call(aaguid: nil, user_agent: FIREFOX_MAC)
  end

  test "uses whichever half of the user agent it recognises" do
    assert_equal "Windows", Passkey::DefaultNickname.call(aaguid: nil, user_agent: "Mozilla/5.0 (Windows NT 10.0)")
    assert_equal "Firefox", Passkey::DefaultNickname.call(aaguid: nil, user_agent: "Firefox/130.0")
  end

  test "falls back to a plain name when nothing is recognised" do
    assert_equal "Passkey", Passkey::DefaultNickname.call(aaguid: nil, user_agent: nil)
    assert_equal "Passkey", Passkey::DefaultNickname.call(aaguid: "unknown", user_agent: "curl/8.0")
  end
end
