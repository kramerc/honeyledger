require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "requires signing in" do
    get dashboard_url
    assert_redirected_to new_session_path
  end

  test "shows the dashboard when signed in" do
    sign_in_as(users(:one))
    get dashboard_url
    assert_response :success
  end

  test "shows the dashboard to a user with no accounts yet" do
    sign_in_as(User.create!(email: "new@example.com", password: "password123"))
    get dashboard_url
    assert_response :success
  end
end
