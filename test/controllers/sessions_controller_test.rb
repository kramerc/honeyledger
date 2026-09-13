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

  test "create never returns to another host, whatever the original Host header said" do
    get accounts_url, headers: { "Host" => "attacker.example" }
    assert_response :redirect

    host! "www.example.com"
    post session_path, params: { email: @user.email, password: "password123" }

    assert_redirected_to "http://www.example.com/accounts"
  end

  test "create does not return to a page that was requested with a non-GET verb" do
    delete session_path
    assert_redirected_to new_session_path

    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_path
  end

  test "a signed-in user is sent home instead of the login form" do
    sign_in_as(@user)

    get new_session_path

    assert_redirected_to root_path
  end

  test "a signed-in user cannot open a second session or switch accounts by logging in again" do
    sign_in_as(@user)
    original_cookie = cookies[:session_id]

    post session_path, params: { email: users(:two).email, password: "password123" }

    assert_redirected_to root_path
    assert_equal original_cookie, cookies[:session_id]
    assert_equal 1, @user.sessions.count
    assert_equal 0, users(:two).sessions.count
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_equal 0, @user.sessions.count
  end

  test "the sign_out helper ends a session that was started through the login form" do
    post session_path, params: { email: @user.email, password: "password123" }
    assert_equal 1, @user.sessions.count

    sign_out

    assert_equal 0, @user.sessions.count
    get accounts_url
    assert_redirected_to new_session_path
  end
end
