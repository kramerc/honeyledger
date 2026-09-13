# Passkeys (WebAuthn) verify that a credential was created for the exact
# origin the page was served from, so the app must know its public origin(s).
#
# Production pins them through WEBAUTHN_ALLOWED_ORIGINS (comma-separated, e.g.
# "https://ledger.example.com") and optionally WEBAUTHN_RP_ID (defaults to the
# first origin's host). Until that is set, passkeys stay hidden in production.
#
# Development and test derive the origin from each request instead, so every
# per-worktree bin/dev port and the integration-test host work without setup.
allowed_origins = ENV.fetch("WEBAUTHN_ALLOWED_ORIGINS", "").split(",").map(&:strip).compact_blank
rp_id = ENV["WEBAUTHN_RP_ID"].presence

# A relying-party id must be a registrable suffix of every allowed origin's
# host. With one origin its host is the obvious choice; with several there is
# no safe guess, so the id has to be given explicitly.
if allowed_origins.many? && rp_id.nil?
  raise "WEBAUTHN_ALLOWED_ORIGINS lists more than one origin, so WEBAUTHN_RP_ID must name the domain they share"
end

Rails.application.config.x.webauthn.allowed_origins = allowed_origins
Rails.application.config.x.webauthn.rp_id = rp_id
Rails.application.config.x.webauthn.derive_origin_from_request = !Rails.env.production?
