require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get show" do
    get integrations_url
    assert_response :success
  end

  test "should show when no connections exist" do
    @user.simplefin_connection&.destroy!
    @user.lunchflow_connection&.destroy!

    get integrations_url
    assert_response :success
  end

  test "requires authentication" do
    sign_out

    get integrations_url
    assert_redirected_to new_session_url
  end

  test "should show with lunchflow connection error" do
    @user.lunchflow_connection.update!(error: "Active subscription required.")

    get integrations_url
    assert_response :success
  end

  test "should show with simplefin errlist" do
    @user.simplefin_connection.update!(errlist: [ { "code" => "auth", "msg" => "Login expired" } ])

    get integrations_url
    assert_response :success
  end
end
