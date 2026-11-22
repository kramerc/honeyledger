# Builds the wallet-relative view of an Ethereum address from an
# Etherscan-compatible explorer (EvmExplorerClient).
#
# An address's ETH moves in two lists: its own transactions (txlist) and value
# moved by contract calls inside any transaction (txlistinternal), which is
# the only place contract-initiated ETH arriving at the address shows up. Both
# are merged by transaction hash, and each hash nets to one movement:
#
# * value in minus value out across the outer transaction and its internal
#   transfers, so a swap that sends ETH and gets some back internally books
#   only the difference;
# * a reverted transaction moves no value, outer or internal, but whoever sent
#   it still paid for the gas.
#
# As with Bitcoin, the gas fee (gasUsed × effective gas price) is a separate
# "fee" row when the wallet sent the transaction, never a split. A token
# transfer, approval, or reverted call therefore yields a fee row alone.
#
# Beacon-chain withdrawals and block rewards credit an address without any
# transaction, so a validator's withdrawal address will read lower than the
# chain. Staking is out of scope for now.
class Blockchain::Ethereum::Scanner
  WEI_PER_ETHER = 10**18
  # A block is final after two epochs (64 slots); shallower ones can reorg.
  FINALITY_DEPTH = 64

  Row = Blockchain::Scan::Row
  Result = Blockchain::Scan::Result

  def self.call(connection, client: connection.client)
    new(connection.identifier, client).call
  end

  def initialize(address, client)
    @address = address.downcase
    @client = client
  end

  def call
    # Read before the history: anything that lands in between is newer than
    # the finality depth, shows up as unconfirmed, and skips the comparison.
    chain_balance_wei = @client.balance(@address)
    normal = @client.normal_transactions(@address)
    internal = @client.internal_transactions(@address)
    tip = @client.block_number

    normal_by_hash = normal.index_by { |entry| entry[:hash] }
    internal_by_hash = internal.group_by { |entry| entry[:hash] }
    hashes = (normal.map { |entry| entry[:hash] } + internal.map { |entry| entry[:hash] }).uniq

    balance_wei = 0
    rows = hashes.flat_map do |hash|
      outer = normal_by_hash[hash]
      # A reverted parent discards every internal transfer. For a hash seen only
      # in the internal list (a contract paying the wallet inside someone else's
      # transaction) each entry's own isError is trusted; Blockscout flags the
      # children of a reverted parent, and issue 373 tracks checking the rest.
      inner = outer&.dig(:failed) ? [] : without_root_trace(outer, Array(internal_by_hash[hash])).reject { |entry| entry[:failed] }
      first = outer || internal_by_hash[hash].first

      net = movement(outer) + inner.sum { |entry| movement(entry) }
      fee = outer && outer[:from] == @address ? outer[:fee] : 0
      confirmed = tip - first[:block_number] + 1 >= FINALITY_DEPTH
      balance_wei += net - fee if confirmed

      [
        row(hash, first, :transfer, net, counterparty(outer, inner, net), confirmed),
        row(hash, first, :fee, -fee, nil, confirmed)
      ].compact
    end

    Result.new(
      balance: to_ether(balance_wei), rows: rows, used_addresses: hashes.any? ? 1 : 0,
      warning: balance_warning(chain_balance_wei, balance_wei, rows)
    )
  end

  BALANCE_MISMATCH_PREFIX = "Balance mismatch:".freeze

  private

    # The chain's balance against what the confirmed history adds up to. ETH
    # that arrives without a listed transaction (beacon withdrawals, block
    # rewards, a protocol-level state change) would otherwise leave the ledger
    # silently wrong. Skipped while any row is unconfirmed, since the node's
    # balance already includes those rows and the history total does not.
    def balance_warning(chain_balance_wei, history_wei, rows)
      return nil if chain_balance_wei.nil? || chain_balance_wei == history_wei
      return nil if rows.any? { |row| !row.confirmed }

      "#{BALANCE_MISMATCH_PREFIX} the chain reports #{to_ether(chain_balance_wei)} ETH but the imported history " \
        "adds up to #{to_ether(history_wei)} ETH (#{to_ether(chain_balance_wei - history_wei)} ETH unexplained). " \
        "ETH that arrives without a transaction, such as staking withdrawals, is not imported; " \
        "add an adjustment to the ledger account to match."
    end

    # Blockscout lists a contract creation's top-level "create" trace in the
    # internal list as well, repeating the outer transaction's value; counting
    # both would move it twice. Ordinary calls get no such root trace.
    def without_root_trace(outer, inner)
      return inner if outer.nil? || outer[:to] || outer[:contract_address].nil?

      index = inner.index do |entry|
        entry[:from] == outer[:from] && entry[:to] == outer[:contract_address] && entry[:value] == outer[:value]
      end
      index ? inner.dup.tap { |entries| entries.delete_at(index) } : inner
    end

    # Signed value an entry moved for the wallet. A self-send nets to zero. A
    # contract creation has no "to"; its value goes to the created contract,
    # which may be the tracked address itself.
    def movement(entry)
      return 0 if entry.nil? || entry[:failed]

      recipient = entry[:to] || entry[:contract_address]
      amount = 0
      amount += entry[:value] if recipient == @address
      amount -= entry[:value] if entry[:from] == @address
      amount
    end

    # Whoever paid the wallet, or whom it paid. For ETH arriving through a
    # contract call (a swap payout) that is the contract that sent it.
    def counterparty(outer, inner, net)
      if net.positive?
        return outer[:from] if outer && outer[:from] != @address && outer[:to] == @address && outer[:value].positive?

        inner.find { |entry| entry[:to] == @address && entry[:value].positive? }&.dig(:from) || outer&.dig(:from)
      else
        return outer[:to] || outer[:contract_address] if outer && outer[:from] == @address && outer[:value].positive?

        inner.find { |entry| entry[:from] == @address && entry[:value].positive? }&.dig(:to) || outer&.dig(:to)
      end
    end

    # Zero amounts are dropped: the transfer leg of a token transfer or a
    # reverted call, or the fee of a transaction someone else sent.
    def row(hash, entry, kind, wei, counterparty, confirmed)
      return nil if wei.zero?

      Row.new(
        remote_id: kind == :fee ? "#{hash}:fee" : hash,
        txid: hash,
        kind: kind.to_s,
        amount: to_ether(wei),
        counterparty: counterparty == @address ? nil : counterparty,
        block_height: entry[:block_number],
        transacted_at: entry[:timestamp],
        confirmed: confirmed
      )
    end

    def to_ether(wei)
      (BigDecimal(wei) / WEI_PER_ETHER).to_s("F")
    end
end
