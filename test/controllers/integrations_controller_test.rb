require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
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
    sign_out @user

    get integrations_url
    assert_redirected_to new_user_session_url
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
