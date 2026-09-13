require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index without signing in" do
    get root_url
    assert_response :success
  end

  test "should get index when signed in" do
    sign_in_as(users(:one))
    get root_url
    assert_response :success
  end
end
