require "test_helper"

module Sessions
  class PasskeysControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
      @passkey = enroll_passkey
      sign_out
    end

    test "options are available without signing in" do
      post passkey_session_options_path, as: :json

      assert_response :success
      body = response.parsed_body
      assert body["challenge"].present?
      assert_equal [], body["allowCredentials"]
      assert_equal "required", body["userVerification"]
      assert_equal "www.example.com", body["rpId"]
    end

    test "options is not found when passkeys are not configured" do
      configuration = Rails.application.config.x.webauthn
      configuration.derive_origin_from_request = false
      post passkey_session_options_path, as: :json
      assert_response :not_found
    ensure
      configuration.derive_origin_from_request = true
    end

    test "create signs in the passkey's user" do
      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: response.parsed_body["challenge"], user_verified: true)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :success
      assert_equal root_url, response.parsed_body["redirect_url"]
      assert cookies[:session_id]
      assert_equal 1, @user.sessions.count
      @passkey.reload
      assert_operator @passkey.sign_count, :>, 0
      assert @passkey.last_used_at.present?
    end

    test "create returns to the page that required authentication" do
      get accounts_url
      assert_redirected_to new_session_path

      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: response.parsed_body["challenge"], user_verified: true)
      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_equal accounts_url, response.parsed_body["redirect_url"]
    end

    test "create rejects an assertion for a different challenge" do
      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: stray_webauthn_challenge, user_verified: true)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
      assert_nil cookies[:session_id]
      assert_equal 0, @user.sessions.count
    end

    test "create rejects a credential the app has never seen" do
      stranger = WebAuthn::FakeClient.new(PasskeyTestHelper::WEBAUTHN_TEST_ORIGIN)
      stranger.create(challenge: stray_webauthn_challenge, user_verified: true)
      post passkey_session_options_path, as: :json
      assertion = stranger.get(challenge: response.parsed_body["challenge"], user_verified: true)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
      assert_nil cookies[:session_id]
    end

    test "create rejects a sign count that went backwards" do
      @passkey.update!(sign_count: 50)
      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: response.parsed_body["challenge"], sign_count: 2, user_verified: true)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
      assert_equal 0, @user.sessions.count
      assert_equal 50, @passkey.reload.sign_count
    end

    test "create rejects an assertion without user verification" do
      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: response.parsed_body["challenge"], user_verified: false)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
      assert_equal 0, @user.sessions.count
    end

    test "create rejects an assertion when no options were requested" do
      assertion = fake_webauthn_client.get(challenge: stray_webauthn_challenge, user_verified: true)

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
    end

    test "create consumes the challenge so an assertion cannot be replayed" do
      post passkey_session_options_path, as: :json
      assertion = fake_webauthn_client.get(challenge: response.parsed_body["challenge"], user_verified: true)
      post passkey_session_path, params: { credential: assertion }, as: :json
      assert_response :success

      post passkey_session_path, params: { credential: assertion }, as: :json

      assert_response :unprocessable_content
      assert_equal 1, @user.sessions.count
    end
  end
end
