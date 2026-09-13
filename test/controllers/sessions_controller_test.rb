require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email: @user.email, password: "password123" }

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal 1, @user.sessions.count
  end

  test "create normalizes the email before matching" do
    post session_path, params: { email: "  ONE@example.com ", password: "password123" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email: @user.email, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    assert_equal "Try another email or password.", flash[:alert]
  end

  test "create returns to the page that required authentication" do
    get accounts_url
    assert_redirected_to new_session_path

    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to accounts_url
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_equal 0, @user.sessions.count
  end
end
