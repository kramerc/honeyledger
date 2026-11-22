# The explorers wallet refreshes query are operator settings, not per-wallet
# ones: a user-supplied URL would let anyone with an account make the server
# request arbitrary (including internal) addresses.

# Bitcoin: an Esplora API. Point ESPLORA_URL at a self-hosted Esplora to keep
# wallet lookups private.
Rails.application.config.x.esplora_url = ENV.fetch("ESPLORA_URL", "https://mempool.space/api")

# Ethereum: an Etherscan-compatible API (EvmExplorerClient::PROVIDERS).
# EVM_EXPLORER picks the provider, "blockscout" (the default; a free Blockscout
# PRO key covers this use) or "etherscan" (whose free, Lite, and Standard
# plans are licensed for personal use only and require attribution).
# EVM_EXPLORER_URL overrides the provider's base URL. Without an API key the
# Ethereum option stays hidden.
Rails.application.config.x.evm_explorer = {
  provider: ENV.fetch("EVM_EXPLORER", "blockscout"),
  base_url: ENV["EVM_EXPLORER_URL"].presence,
  api_key: ENV["EVM_EXPLORER_API_KEY"].presence || Rails.application.credentials.dig(:evm_explorer, :api_key)
}
