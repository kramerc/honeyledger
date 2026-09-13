# Enrols and removes passkeys for the signed-in user. `options` and `create`
# are the two halves of a WebAuthn registration ceremony and are called from
# the passkey Stimulus controller with JSON.
class PasskeysController < ApplicationController
  include RecentAuthentication

  before_action :require_passkeys, only: %i[ options create ]
  before_action :require_recent_authentication, only: %i[ options create ]

  def options
    creation_options = webauthn_relying_party.options_for_registration(
      user: { id: current_user.webauthn_id, name: current_user.email, display_name: current_user.email },
      exclude: current_user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", require_resident_key: true, user_verification: "required" }
    )
    session[:passkey_creation_challenge] = creation_options.challenge

    render json: creation_options
  end

  def create
    challenge = session.delete(:passkey_creation_challenge)
    return head :unprocessable_content if challenge.blank?

    webauthn_credential = webauthn_relying_party.verify_registration(credential_params.to_h, challenge, user_verification: true)
    current_user.passkeys.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: params[:nickname].presence || "Passkey"
    )

    flash[:notice] = "Passkey added."
    render json: { redirect_url: settings_path }, status: :created
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid => error
    render json: { error: error.message }, status: :unprocessable_content
  end

  def destroy
    current_user.passkeys.find(params[:id]).destroy!

    redirect_to settings_path, notice: "Passkey removed.", status: :see_other
  end

  private
    def credential_params
      params.require(:credential).permit(
        :id, :rawId, :type, :authenticatorAttachment,
        response: [ :attestationObject, :clientDataJSON, :authenticatorData, :publicKey, :publicKeyAlgorithm, transports: [] ],
        clientExtensionResults: {}
      )
    end
end
