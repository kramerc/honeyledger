require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index without signing in" do
    get root_url
    assert_response :success
  end

  test "sends a signed-in user to the dashboard" do
    sign_in_as(users(:one))
    get root_url
    assert_redirected_to dashboard_path
  end

  # The row action menus need the Popover API, which Firefox shipped in 125.
  test "turns away Firefox older than 125" do
    get root_url, headers: { "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0" }
    assert_response :not_acceptable
  end

  test "admits Firefox 125" do
    get root_url, headers: { "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0" }
    assert_response :success
  end
end
