# Logs a user in with a passkey. Usernameless: the options carry no
# allowCredentials, so the browser's account picker chooses the credential and
# the server looks the user up from the credential id it signs back.
module Sessions
  class PasskeysController < ApplicationController
    allow_unauthenticated_access
    before_action :require_passkeys
    rate_limit to: 10, within: 3.minutes, with: -> { head :too_many_requests }

    def options
      request_options = webauthn_relying_party.options_for_authentication(allow: [], user_verification: "required")
      session[:passkey_authentication_challenge] = request_options.challenge

      render json: request_options
    end

    def create
      challenge = session.delete(:passkey_authentication_challenge)
      return head :unprocessable_content if challenge.blank?

      webauthn_credential, passkey = webauthn_relying_party.verify_authentication(credential_params.to_h, challenge, user_verification: true) do |presented_credential|
        Passkey.find_by!(external_id: presented_credential.id)
      end
      passkey.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
      start_new_session_for passkey.user

      render json: { redirect_url: after_authentication_url }
    rescue WebAuthn::Error, ActiveRecord::RecordNotFound
      head :unprocessable_content
    end

    private
      def credential_params
        params.require(:credential).permit(
          :id, :rawId, :type, :authenticatorAttachment,
          response: %i[ authenticatorData clientDataJSON signature userHandle ],
          clientExtensionResults: {}
        )
      end
  end
end
