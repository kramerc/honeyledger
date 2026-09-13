require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "show requires a signed-in user" do
    get settings_path

    assert_redirected_to new_session_path
  end

  test "show" do
    sign_in_as(users(:one))

    get settings_path

    assert_response :success
  end

  test "show renders when the session is no longer recent" do
    user = users(:one)
    sign_in_as(user)
    user.sessions.last.update!(created_at: 1.hour.ago)

    get settings_path

    assert_response :success
  end
end
