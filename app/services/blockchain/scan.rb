# What a chain scanner hands Blockchain::RefreshJob, whatever the chain.
module Blockchain::Scan
  # One wallet-relative movement: a "transfer" (remote_id = transaction hash)
  # or the "fee" the wallet paid for it (remote_id = "<hash>:fee"). amount is a
  # signed decimal string in whole coins.
  Row = Data.define(:remote_id, :txid, :kind, :amount, :counterparty, :block_height, :transacted_at, :confirmed)

  # balance: the wallet's confirmed balance in whole coins. used_addresses: how
  # many of the wallet's addresses have ever been used; zero for a Bitcoin
  # extended key usually means the wrong key type. warning: a problem worth
  # showing on the wallet that did not stop the scan, such as a balance the
  # history does not explain.
  Result = Data.define(:balance, :rows, :used_addresses, :warning) do
    def initialize(balance:, rows:, used_addresses:, warning: nil)
      super
    end
  end
end
