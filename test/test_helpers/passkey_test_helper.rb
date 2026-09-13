require "webauthn/fake_client"

module PasskeyTestHelper
  # Integration tests run against this host, and outside production the
  # relying party derives its origin from the request, so a fake client here
  # produces credentials the app accepts.
  WEBAUTHN_TEST_ORIGIN = "http://www.example.com"

  def fake_webauthn_client
    @fake_webauthn_client ||= WebAuthn::FakeClient.new(WEBAUTHN_TEST_ORIGIN)
  end

  # Enrols a passkey for the signed-in user through the real endpoints and
  # returns the stored record. Leaves `response` on the final POST.
  def enroll_passkey(nickname: "Laptop", client: fake_webauthn_client)
    post options_passkeys_path, as: :json
    credential = client.create(challenge: response.parsed_body["challenge"], user_verified: true)
    post passkeys_path, params: { nickname: nickname, credential: credential }, as: :json

    Passkey.find_by!(external_id: credential["id"])
  end

  # A challenge the server never issued.
  def stray_webauthn_challenge
    WebAuthn.standard_encoder.encode(SecureRandom.random_bytes(32))
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include PasskeyTestHelper
end
