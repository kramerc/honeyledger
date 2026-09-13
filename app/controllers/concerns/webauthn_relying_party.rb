# Builds the WebAuthn relying party for the current request. See
# config/initializers/webauthn.rb for where the origins come from.
module WebauthnRelyingParty
  extend ActiveSupport::Concern

  included do
    helper_method :passkeys_available?
  end

  private
    def passkeys_available?
      webauthn_allowed_origins.any?
    end

    def require_passkeys
      head :not_found unless passkeys_available?
    end

    def webauthn_relying_party
      @webauthn_relying_party ||= WebAuthn::RelyingParty.new(
        allowed_origins: webauthn_allowed_origins,
        id: webauthn_configuration.rp_id || URI.parse(webauthn_allowed_origins.first).host,
        name: "Honeyledger"
      )
    end

    def webauthn_allowed_origins
      configured_origins = webauthn_configuration.allowed_origins
      return configured_origins if configured_origins.any?

      webauthn_configuration.derive_origin_from_request ? [ request.base_url ] : []
    end

    def webauthn_configuration
      Rails.application.config.x.webauthn
    end
end
