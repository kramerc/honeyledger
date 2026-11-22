# Ethereum wallets are only offered when the operator has configured an EVM
# explorer API key. Tests that add one configure a placeholder key for the
# duration of the block; nothing ever reaches the network with it.
module EvmExplorerTestHelper
  TEST_API_KEY = "test-explorer-key".freeze

  def with_evm_explorer(api_key: TEST_API_KEY, provider: "blockscout")
    original = Rails.configuration.x.evm_explorer
    Rails.configuration.x.evm_explorer = original.merge(api_key: api_key, provider: provider)
    yield
  ensure
    Rails.configuration.x.evm_explorer = original
  end
end

ActiveSupport::TestCase.include(EvmExplorerTestHelper)
