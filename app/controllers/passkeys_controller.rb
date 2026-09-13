# Enrols, renames, and removes passkeys for the signed-in user. `options` and
# `create` are the two halves of a WebAuthn registration ceremony and are
# called from the passkey Stimulus controller with JSON.
class PasskeysController < ApplicationController
  include RecentAuthentication

  before_action :require_passkeys, only: %i[ options create ]
  before_action :require_recent_authentication, only: %i[ options create ]
  before_action :set_passkey, only: %i[ edit update destroy ]

  def options
    creation_options = webauthn_relying_party.options_for_registration(
      user: { id: current_user.webauthn_id, name: current_user.email, display_name: current_user.email },
      exclude: current_user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", require_resident_key: true, user_verification: "required" }
    )
    challenge = WebauthnChallenge.issue(purpose: "registration", challenge: creation_options.challenge, user: current_user)
    session[:passkey_registration_challenge_id] = challenge.id

    render json: creation_options
  end

  def create
    challenge = WebauthnChallenge.consume(session.delete(:passkey_registration_challenge_id), purpose: "registration", user: current_user)
    if challenge.nil?
      return render json: { error: "This passkey request has expired. Please try again." }, status: :unprocessable_content
    end

    webauthn_credential = webauthn_relying_party.verify_registration(credential_params.to_h, challenge, user_verification: true)
    current_user.passkeys.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: params[:nickname].presence || default_nickname_for(webauthn_credential)
    )

    flash[:notice] = "Passkey added."
    render json: { redirect_url: settings_path }, status: :created
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid => error
    render json: { error: error.message }, status: :unprocessable_content
  end

  def edit
  end

  def update
    if @passkey.update(passkey_params)
      redirect_to settings_path, notice: "Passkey renamed.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @passkey.destroy!

    redirect_to settings_path, notice: "Passkey removed.", status: :see_other
  end

  private
    def set_passkey
      @passkey = current_user.passkeys.find(params[:id])
    end

    def passkey_params
      params.expect(passkey: [ :nickname ])
    end

    def default_nickname_for(webauthn_credential)
      Passkey::DefaultNickname.call(aaguid: webauthn_credential.response.aaguid, user_agent: request.user_agent)
    end

    def credential_params
      params.require(:credential).permit(
        :id, :rawId, :type, :authenticatorAttachment,
        response: [ :attestationObject, :clientDataJSON, :authenticatorData, :publicKey, :publicKeyAlgorithm, transports: [] ],
        clientExtensionResults: {}
      )
    end
end
