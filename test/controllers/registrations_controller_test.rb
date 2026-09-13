require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "create signs the new user in" do
    assert_difference("User.count", 1) do
      post registration_path, params: { user: { email: "new@example.com", password: "password123", password_confirmation: "password123" } }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal "new@example.com", User.last.email
  end

  test "create rejects a duplicate email" do
    assert_no_difference("User.count") do
      post registration_path, params: { user: { email: "ONE@example.com", password: "password123", password_confirmation: "password123" } }
    end

    assert_response :unprocessable_content
    assert_nil cookies[:session_id]
  end

  test "create rejects a short password" do
    assert_no_difference("User.count") do
      post registration_path, params: { user: { email: "new@example.com", password: "short", password_confirmation: "short" } }
    end

    assert_response :unprocessable_content
  end

  test "create rejects a mismatched confirmation" do
    assert_no_difference("User.count") do
      post registration_path, params: { user: { email: "new@example.com", password: "password123", password_confirmation: "different1" } }
    end

    assert_response :unprocessable_content
  end
end
