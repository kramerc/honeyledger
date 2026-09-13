require "test_helper"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "options requires a signed-in user" do
    sign_out

    post options_passkeys_path, as: :json

    assert_redirected_to new_session_path
  end

  test "options returns creation options that exclude the user's existing passkeys" do
    post options_passkeys_path, as: :json

    assert_response :success
    body = response.parsed_body
    assert body["challenge"].present?
    assert_equal "Honeyledger", body["rp"]["name"]
    assert_equal "www.example.com", body["rp"]["id"]
    assert_equal @user.email, body["user"]["name"]
    assert_equal "required", body["authenticatorSelection"]["userVerification"]
    assert_equal [ passkeys(:laptop).external_id ], body["excludeCredentials"].map { |descriptor| descriptor["id"] }
  end

  test "options is refused when the session is not recent" do
    @user.sessions.last.update!(created_at: 1.hour.ago)

    post options_passkeys_path, as: :json

    assert_response :forbidden
  end

  test "a non-JSON request from a stale session is sent to confirm the password" do
    @user.sessions.last.update!(created_at: 1.hour.ago)

    post options_passkeys_path

    assert_redirected_to new_reauthentication_path
  end

  test "options is allowed again after the password is confirmed" do
    @user.sessions.last.update!(created_at: 1.hour.ago)
    post reauthentication_path, params: { password: "password123" }

    post options_passkeys_path, as: :json

    assert_response :success
  end

  test "options is not found when passkeys are not configured" do
    without_passkeys do
      post options_passkeys_path, as: :json
    end

    assert_response :not_found
  end

  test "create stores the verified credential" do
    assert_difference("Passkey.count", 1) do
      passkey = enroll_passkey(nickname: "Phone")

      assert_equal @user, passkey.user
      assert_equal "Phone", passkey.nickname
      assert passkey.public_key.present?
    end

    assert_response :created
    assert_equal settings_path, response.parsed_body["redirect_url"]
    assert_equal "Passkey added.", flash[:notice]
  end

  test "create falls back to a default nickname" do
    passkey = enroll_passkey(nickname: "")

    assert_equal "Passkey", passkey.nickname
  end

  test "create rejects a credential made for a different challenge" do
    post options_passkeys_path, as: :json
    credential = fake_webauthn_client.create(challenge: stray_webauthn_challenge, user_verified: true)

    assert_no_difference("Passkey.count") do
      post passkeys_path, params: { nickname: "Phone", credential: credential }, as: :json
    end

    assert_response :unprocessable_content
    assert response.parsed_body["error"].present?
  end

  test "create rejects a credential without user verification" do
    post options_passkeys_path, as: :json
    credential = fake_webauthn_client.create(challenge: response.parsed_body["challenge"], user_verified: false)

    assert_no_difference("Passkey.count") do
      post passkeys_path, params: { nickname: "Phone", credential: credential }, as: :json
    end

    assert_response :unprocessable_content
  end

  test "create rejects a credential when no options were requested" do
    credential = fake_webauthn_client.create(challenge: stray_webauthn_challenge, user_verified: true)

    assert_no_difference("Passkey.count") do
      post passkeys_path, params: { nickname: "Phone", credential: credential }, as: :json
    end

    assert_response :unprocessable_content
  end

  test "create consumes the challenge so a credential cannot be replayed" do
    post options_passkeys_path, as: :json
    credential = fake_webauthn_client.create(challenge: response.parsed_body["challenge"], user_verified: true)
    post passkeys_path, params: { nickname: "Phone", credential: credential }, as: :json
    assert_response :created

    assert_no_difference("Passkey.count") do
      post passkeys_path, params: { nickname: "Phone again", credential: credential }, as: :json
    end

    assert_response :unprocessable_content
  end

  test "destroy removes the user's own passkey" do
    assert_difference("Passkey.count", -1) do
      delete passkey_path(passkeys(:laptop))
    end

    assert_redirected_to settings_path
  end

  test "destroy cannot remove another user's passkey" do
    assert_no_difference("Passkey.count") do
      delete passkey_path(passkeys(:phone))
    end

    assert_response :not_found
  end

  private
    def without_passkeys
      configuration = Rails.application.config.x.webauthn
      configuration.derive_origin_from_request = false
      yield
    ensure
      configuration.derive_origin_from_request = true
    end
end
