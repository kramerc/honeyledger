require "test_helper"

class ReauthenticationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "new requires a signed-in user" do
    sign_out

    get new_reauthentication_path

    assert_redirected_to new_session_path
  end

  test "new" do
    get new_reauthentication_path

    assert_response :success
  end

  test "create with the right password confirms and returns to settings" do
    post reauthentication_path, params: { password: "password123" }

    assert_redirected_to settings_path
    assert_equal "Password confirmed.", flash[:notice]
  end

  test "create with the wrong password goes back to the form" do
    post reauthentication_path, params: { password: "wrong" }

    assert_redirected_to new_reauthentication_path
    assert_equal "That password is not right.", flash[:alert]
  end

  test "create without a password goes back to the form" do
    post reauthentication_path

    assert_redirected_to new_reauthentication_path
  end
end
