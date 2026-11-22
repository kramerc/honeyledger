# Builds the wallet-relative view of a Bitcoin wallet from an Esplora-style
# client: which addresses belong to it, and what each on-chain transaction did
# to its balance.
#
# For an extended public key the receive (0) and change (1) branches are
# scanned until GAP_LIMIT consecutive addresses have never been used, and the
# derived addresses are cached on the connection so later refreshes resume
# from the frontier. A single-address wallet is just that address.
#
# Each transaction is netted against the wallet's whole address set, so change
# returning to one of the wallet's own addresses cancels out instead of looking
# like an outflow:
#
# * No input from the wallet: a receipt of what it was paid.
# * Every input from the wallet: the wallet paid the fee. The transfer row is
#   the net movement excluding the fee, and a separate fee row carries it.
# * Some inputs from the wallet (a coinjoin or payjoin): who paid how much fee
#   is not knowable from the chain, so one row carries the whole net movement.
class Blockchain::Bitcoin::Scanner
  GAP_LIMIT = 20
  SATOSHIS_PER_COIN = 100_000_000

  Row = Blockchain::Scan::Row
  Result = Blockchain::Scan::Result

  def self.call(connection, client: connection.client)
    new(connection, client).call
  end

  def initialize(connection, client)
    @connection = connection
    @client = client
  end

  def call
    used_addresses, owned = discover_addresses

    transactions = used_addresses
      .flat_map { |address| @client.address_transactions(address) }
      .uniq { |transaction| transaction[:txid] }
      .select { |transaction| transaction[:confirmed] }

    balance_satoshis = 0
    rows = transactions.flat_map do |transaction|
      received = transaction[:outputs].sum { |output| owned.include?(output[:address]) ? output[:value] : 0 }
      spent = transaction[:inputs].sum { |input| owned.include?(input[:address]) ? input[:value] : 0 }
      balance_satoshis += received - spent

      rows_for(transaction, owned, received, spent)
    end

    Result.new(balance: to_coins(balance_satoshis), rows: rows, used_addresses: used_addresses.size)
  end

  private

    # Returns [addresses to fetch history for, every address the wallet owns].
    # Ownership covers every derived address, not just the ones known to be
    # used: a transaction that confirms mid-scan can pay change to an address
    # still marked unused, and must net that change out rather than book it as
    # a send.
    def discover_addresses
      key = @connection.extended_key
      return [ [ @connection.identifier ], Set[@connection.identifier] ] if key.nil?

      [ Blockchain::Address::RECEIVE, Blockchain::Address::CHANGE ].each do |branch|
        scan_branch(key, branch)
      end

      addresses = @connection.addresses.order(:branch, :index).pluck(:address, :used)
      [ addresses.select(&:last).map(&:first), addresses.map(&:first).to_set ]
    end

    def scan_branch(key, branch)
      cached = @connection.addresses.where(branch: branch).order(:index).to_a

      # An address that has been used stays used; only the unused tail can change.
      cached.reject(&:used).each do |address_record|
        address_record.update!(used: true) if used?(address_record.address)
      end

      trailing_unused = cached.reverse.take_while { |address_record| !address_record.used }.size
      next_index = cached.empty? ? 0 : cached.last.index + 1

      while trailing_unused < GAP_LIMIT
        address = key.address_at(branch, next_index)
        used = used?(address)
        @connection.addresses.create!(branch: branch, index: next_index, address: address, used: used)
        trailing_unused = used ? 0 : trailing_unused + 1
        next_index += 1
      end
    end

    def used?(address)
      @client.address_stats(address)[:tx_count].positive?
    end

    def rows_for(transaction, owned, received, spent)
      inputs_from_wallet = transaction[:inputs].count { |input| owned.include?(input[:address]) }

      if inputs_from_wallet.zero?
        counterparty = first_foreign_address(transaction[:inputs], owned)
        [ row(transaction, :transfer, received, counterparty) ].compact
      elsif inputs_from_wallet == transaction[:inputs].size
        fee = transaction[:fee]
        counterparty = first_foreign_address(transaction[:outputs], owned)
        [
          row(transaction, :transfer, received - spent + fee, counterparty),
          row(transaction, :fee, -fee, nil)
        ].compact
      else
        # Net inflow (a payjoin receive): the payer is among the foreign inputs.
        # Net outflow (a coinjoin send): the payee is among the foreign outputs.
        net = received - spent
        counterparty = first_foreign_address(net.positive? ? transaction[:inputs] : transaction[:outputs], owned)
        [ row(transaction, :transfer, net, counterparty) ].compact
      end
    end

    # A zero-amount row would import as an empty ledger transaction, e.g. the
    # transfer leg of a consolidation that only moved coins between the
    # wallet's own addresses (its fee row still carries the cost).
    def row(transaction, kind, satoshis, counterparty)
      return nil if satoshis.zero?

      Row.new(
        remote_id: kind == :fee ? "#{transaction[:txid]}:fee" : transaction[:txid],
        txid: transaction[:txid],
        kind: kind.to_s,
        amount: to_coins(satoshis),
        counterparty: counterparty,
        block_height: transaction[:block_height],
        transacted_at: transaction[:block_time],
        confirmed: transaction[:confirmed]
      )
    end

    def first_foreign_address(entries, owned)
      entries.map { |entry| entry[:address] }.compact.find { |address| !owned.include?(address) }
    end

    def to_coins(satoshis)
      (BigDecimal(satoshis) / SATOSHIS_PER_COIN).to_s("F")
    end
end
