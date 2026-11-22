# The Esplora API wallet refreshes query. It is an operator setting, not a
# per-wallet one: a user-supplied URL would let anyone with an account make the
# server request arbitrary (including internal) addresses. Point ESPLORA_URL at
# a self-hosted Esplora to keep wallet lookups private.
Rails.application.config.x.esplora_url = ENV.fetch("ESPLORA_URL", "https://mempool.space/api")
