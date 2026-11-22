require "test_helper"

class Blockchain::Bitcoin::ScannerTest < ActiveSupport::TestCase
  ZPUB = "zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs".freeze

  # BIP84 vector addresses for the zpub above.
  RECEIVE_0 = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu".freeze
  RECEIVE_1 = "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g".freeze
  CHANGE_0 = "bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el".freeze

  # Addresses outside the wallet (BIP173 example and the generator key's P2PKH).
  FOREIGN = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4".freeze
  OTHER_FOREIGN = "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH".freeze

  # An in-memory Esplora: answers stats and history from a fixed transaction list.
  class FakeClient
    attr_reader :stats_calls

    def initialize(transactions)
      @transactions = transactions
      @stats_calls = []
    end

    def address_stats(address)
      @stats_calls << address
      { tx_count: touching(address).size, funded: 0, spent: 0 }
    end

    def address_transactions(address)
      touching(address)
    end

    private

      def touching(address)
        @transactions.select do |transaction|
          (transaction[:inputs] + transaction[:outputs]).any? { |entry| entry[:address] == address }
        end
      end
  end

  setup do
    @connection = Blockchain::Connection.create!(user: users(:two), chain: "bitcoin", name: "Test wallet", identifier: ZPUB)
  end

  test "a receipt is one positive transfer row from the sender" do
    result = scan(transaction("aa", inputs: [ [ FOREIGN, 150_000 ] ], outputs: [ [ RECEIVE_0, 100_000 ], [ FOREIGN, 49_000 ] ], fee: 1_000))

    assert_equal 1, result.rows.size
    row = result.rows.first
    assert_equal "aa", row.remote_id
    assert_equal "transfer", row.kind
    assert_equal "0.001", row.amount
    assert_equal FOREIGN, row.counterparty
    assert_equal "0.001", result.balance
  end

  test "a send nets out change and emits a separate fee row" do
    result = scan(
      transaction("aa", inputs: [ [ FOREIGN, 150_000 ] ], outputs: [ [ RECEIVE_0, 100_000 ] ], fee: 50_000),
      transaction("bb", inputs: [ [ RECEIVE_0, 100_000 ] ], outputs: [ [ OTHER_FOREIGN, 60_000 ], [ CHANGE_0, 39_000 ] ], fee: 1_000)
    )

    transfer = result.rows.find { |row| row.remote_id == "bb" }
    fee = result.rows.find { |row| row.remote_id == "bb:fee" }

    assert_equal "-0.0006", transfer.amount
    assert_equal OTHER_FOREIGN, transfer.counterparty
    assert_equal "fee", fee.kind
    assert_equal "-0.00001", fee.amount
    assert_nil fee.counterparty
    assert_equal "0.00039", result.balance
  end

  test "moving coins between the wallet's own addresses leaves only the fee" do
    result = scan(
      transaction("aa", inputs: [ [ FOREIGN, 300_000 ] ], outputs: [ [ RECEIVE_0, 100_000 ], [ RECEIVE_1, 100_000 ] ], fee: 100_000),
      transaction("bb", inputs: [ [ RECEIVE_0, 100_000 ], [ RECEIVE_1, 100_000 ] ], outputs: [ [ CHANGE_0, 199_000 ] ], fee: 1_000)
    )

    consolidation_rows = result.rows.select { |row| row.txid == "bb" }
    assert_equal [ "bb:fee" ], consolidation_rows.map(&:remote_id)
    assert_equal "-0.00001", consolidation_rows.first.amount
    assert_equal "0.00199", result.balance
  end

  test "a transaction only partly funded by the wallet is one net row with no fee split" do
    result = scan(
      transaction("aa", inputs: [ [ FOREIGN, 100_000 ] ], outputs: [ [ RECEIVE_0, 50_000 ] ], fee: 50_000),
      transaction("bb", inputs: [ [ RECEIVE_0, 50_000 ], [ FOREIGN, 50_000 ] ], outputs: [ [ RECEIVE_1, 49_500 ], [ FOREIGN, 49_500 ] ], fee: 1_000)
    )

    coinjoin_rows = result.rows.select { |row| row.txid == "bb" }
    assert_equal 1, coinjoin_rows.size
    assert_equal "transfer", coinjoin_rows.first.kind
    assert_equal "-0.000005", coinjoin_rows.first.amount
  end

  test "unconfirmed transactions are left out" do
    result = scan(transaction("aa", inputs: [ [ FOREIGN, 10_000 ] ], outputs: [ [ RECEIVE_0, 9_000 ] ], fee: 1_000, confirmed: false))

    assert_empty result.rows
    assert_equal "0.0", result.balance
  end

  test "scans each branch until twenty unused addresses in a row" do
    scan(transaction("aa", inputs: [ [ FOREIGN, 10_000 ] ], outputs: [ [ RECEIVE_0, 5_000 ], [ CHANGE_0, 4_000 ] ], fee: 1_000))

    receive = @connection.addresses.where(branch: Blockchain::Address::RECEIVE).order(:index)
    change = @connection.addresses.where(branch: Blockchain::Address::CHANGE).order(:index)
    assert_equal 21, receive.count
    assert_equal 21, change.count
    assert_equal [ RECEIVE_0 ], receive.where(used: true).pluck(:address)
    assert_equal RECEIVE_1, receive.second.address
    assert_equal [ CHANGE_0 ], change.where(used: true).pluck(:address)
  end

  test "a later refresh resumes from the cached frontier" do
    funding = transaction("aa", inputs: [ [ FOREIGN, 10_000 ] ], outputs: [ [ RECEIVE_0, 9_000 ] ], fee: 1_000)
    scan(funding)
    assert_equal 21, @connection.addresses.where(branch: 0).count

    receive_5 = BitcoinExtendedKey.parse(ZPUB).address_at(0, 5)
    client = FakeClient.new([ funding, transaction("bb", inputs: [ [ FOREIGN, 10_000 ] ], outputs: [ [ receive_5, 9_000 ] ], fee: 1_000) ])
    Blockchain::Bitcoin::Scanner.call(@connection, client: client)

    assert_not_includes client.stats_calls, RECEIVE_0, "an address already known to be used is not re-checked"
    assert @connection.addresses.find_by(address: receive_5).used
    assert_equal 26, @connection.addresses.where(branch: 0).count, "twenty unused addresses follow the newly used index 5"
  end

  test "a single-address wallet scans just that address" do
    connection = blockchain_connections(:address_wallet)
    client = FakeClient.new([ transaction("aa", inputs: [ [ RECEIVE_0, 10_000 ] ], outputs: [ [ FOREIGN, 9_000 ] ], fee: 1_000) ])

    result = Blockchain::Bitcoin::Scanner.call(connection, client: client)

    assert_empty client.stats_calls
    assert_equal 0, connection.addresses.count
    assert_equal [ "0.00009" ], result.rows.map(&:amount)
    assert_equal RECEIVE_0, result.rows.first.counterparty
  end

  private

    def scan(*transactions)
      Blockchain::Bitcoin::Scanner.call(@connection, client: FakeClient.new(transactions))
    end

    def transaction(txid, inputs:, outputs:, fee:, confirmed: true)
      {
        txid: txid,
        fee: fee,
        block_height: 800_000,
        block_time: Time.zone.parse("2026-04-20 12:00"),
        confirmed: confirmed,
        inputs: inputs.map { |address, value| { address: address, value: value } },
        outputs: outputs.map { |address, value| { address: address, value: value } }
      }
    end
end
