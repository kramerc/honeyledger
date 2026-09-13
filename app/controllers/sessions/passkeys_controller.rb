# Logs a user in with a passkey. Usernameless: the options carry no
# allowCredentials, so the browser's account picker chooses the credential and
# the server looks the user up from the credential id it signs back.
module Sessions
  class PasskeysController < ApplicationController
    allow_unauthenticated_access
    before_action :require_passkeys
    before_action :reject_signed_in_users
    rate_limit to: 10, within: 3.minutes, with: -> { head :too_many_requests }

    def options
      request_options = webauthn_relying_party.options_for_authentication(allow: [], user_verification: "required")
      challenge = WebauthnChallenge.issue(purpose: "authentication", challenge: request_options.challenge)
      session[:passkey_authentication_challenge_id] = challenge.id

      render json: request_options
    end

    def create
      challenge = WebauthnChallenge.consume(session.delete(:passkey_authentication_challenge_id), purpose: "authentication")
      if challenge.nil?
        return render json: { error: "This sign-in request has expired. Please try again." }, status: :unprocessable_content
      end

      passkey = Passkey.transaction do
        webauthn_credential, locked_passkey = webauthn_relying_party.verify_authentication(credential_params.to_h, challenge, user_verification: true) do |presented_credential|
          # Locked so a concurrent assertion waits and then sees the advanced
          # counter, instead of both verifying against the same stale value.
          Passkey.lock.find_by!(external_id: presented_credential.id)
        end
        locked_passkey.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
        locked_passkey
      end
      start_new_session_for passkey.user

      render json: { redirect_url: after_authentication_url }
    rescue WebAuthn::Error, ActiveRecord::RecordNotFound
      render json: { error: "That passkey was not accepted. Try again, or log in with your password." }, status: :unprocessable_content
    end

    private
      # The JSON counterpart of Authentication#redirect_signed_in_users: a
      # browser that already holds a session must not open a second one.
      def reject_signed_in_users
        render json: { error: "You are already logged in." }, status: :forbidden if authenticated?
      end

      def credential_params
        params.require(:credential).permit(
          :id, :rawId, :type, :authenticatorAttachment,
          response: %i[ authenticatorData clientDataJSON signature userHandle ],
          clientExtensionResults: {}
        )
      end
  end
end
