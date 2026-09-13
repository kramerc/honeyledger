# Passkeys (WebAuthn) verify that a credential was created for the exact
# origin the page was served from, so the app must know its public origin(s).
#
# Production pins them through WEBAUTHN_ALLOWED_ORIGINS (comma-separated, e.g.
# "https://ledger.example.com") and optionally WEBAUTHN_RP_ID (defaults to the
# first origin's host). Until that is set, passkeys stay hidden in production.
#
# Development and test derive the origin from each request instead, so every
# per-worktree bin/dev port and the integration-test host work without setup.
Rails.application.config.x.webauthn.allowed_origins =
  ENV.fetch("WEBAUTHN_ALLOWED_ORIGINS", "").split(",").map(&:strip).compact_blank
Rails.application.config.x.webauthn.rp_id = ENV["WEBAUTHN_RP_ID"].presence
Rails.application.config.x.webauthn.derive_origin_from_request = !Rails.env.production?
