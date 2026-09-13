require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email: @user.email }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path
    assert_match(/reset instructions sent/, flash[:notice])
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path
    assert_match(/reset instructions sent/, flash[:notice])
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path
    assert_match(/reset link is invalid/, flash[:alert])
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "newpassword1", password_confirmation: "newpassword1" }
      assert_redirected_to new_session_path
    end

    assert_equal "Password has been reset.", flash[:notice]
    assert @user.reload.authenticate("newpassword1")
  end

  test "update signs out every existing session" do
    sign_in_as(@user)
    token = @user.password_reset_token

    put password_path(token), params: { password: "newpassword1", password_confirmation: "newpassword1" }

    assert_equal 0, @user.sessions.count
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "newpassword1", password_confirmation: "mismatch1" }
      assert_redirected_to edit_password_path(token)
    end

    assert_match(/Password confirmation doesn't match/, flash[:alert])
  end

  test "update with a too-short password" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "short" }
      assert_redirected_to edit_password_path(token)
    end

    assert_match(/Password is too short/, flash[:alert])
  end
end
