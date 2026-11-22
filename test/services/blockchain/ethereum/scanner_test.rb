require "test_helper"

class Blockchain::Ethereum::ScannerTest < ActiveSupport::TestCase
  # EIP-55 example addresses; hashes are placeholders.
  WALLET = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed".freeze
  PAYER = "0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359".freeze
  PAYEE = "0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb".freeze
  ROUTER = "0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb".freeze
  ETHER = 10**18
  FEE = 21_000 * 20_000_000_000 # 0.00042 ETH
  TIP = 20_000_000

  # chain_balance nil: the explorer reported nothing to compare against.
  FakeClient = Struct.new(:normal, :internal, :tip, :chain_balance) do
    def balance(_address) = chain_balance
    def normal_transactions(_address) = normal
    def internal_transactions(_address) = internal
    def block_number = tip
  end

  test "a receipt is one transfer row from the payer" do
    result = scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: 2 * ETHER) ])

    row = result.rows.sole
    assert_equal [ tx_hash("a"), tx_hash("a"), "transfer", "2.0", PAYER, true ],
      [ row.remote_id, row.txid, row.kind, row.amount, row.counterparty, row.confirmed ]
    assert_equal "2.0", result.balance
    assert_equal 1, result.used_addresses
  end

  test "a send is a transfer row plus a fee row the wallet paid" do
    result = scan(normal: [
      normal_tx("a", from: PAYER, to: WALLET, value: ETHER),
      normal_tx("b", from: WALLET, to: PAYEE, value: ETHER / 4)
    ])

    transfer, fee = result.rows.last(2)
    assert_equal [ tx_hash("b"), "transfer", "-0.25", PAYEE ], [ transfer.remote_id, transfer.kind, transfer.amount, transfer.counterparty ]
    assert_equal [ "#{tx_hash("b")}:fee", "fee", "-0.00042", nil ], [ fee.remote_id, fee.kind, fee.amount, fee.counterparty ]
    assert_equal "0.74958", result.balance
  end

  test "a reverted send moves nothing but still costs gas" do
    result = scan(normal: [ normal_tx("a", from: WALLET, to: PAYEE, value: ETHER, failed: true) ],
                  internal: [ internal_tx("a", from: PAYEE, to: WALLET, value: ETHER, failed: true) ])

    assert_equal [ "fee" ], result.rows.map(&:kind)
    assert_equal "-0.00042", result.balance
  end

  test "someone else's reverted payment leaves no rows" do
    assert_empty scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: ETHER, failed: true) ]).rows
  end

  test "contract-initiated ETH appears only in the internal list" do
    result = scan(internal: [ internal_tx("a", from: ROUTER, to: WALLET, value: ETHER / 2) ])

    row = result.rows.sole
    assert_equal [ "transfer", "0.5", ROUTER ], [ row.kind, row.amount, row.counterparty ]
    assert_equal "0.5", result.balance
  end

  test "a swap that sends ETH and gets some back nets to the difference" do
    result = scan(
      normal: [ normal_tx("a", from: WALLET, to: ROUTER, value: ETHER) ],
      internal: [ internal_tx("a", from: ROUTER, to: WALLET, value: ETHER / 4) ]
    )

    transfer, fee = result.rows
    assert_equal [ "-0.75", ROUTER ], [ transfer.amount, transfer.counterparty ]
    assert_equal "-0.00042", fee.amount
  end

  test "a swap paying out ETH credits the wallet from the contract" do
    result = scan(
      normal: [ normal_tx("a", from: WALLET, to: ROUTER, value: 0) ],
      internal: [ internal_tx("a", from: ROUTER, to: WALLET, value: 3 * ETHER), internal_tx("a", from: ROUTER, to: PAYEE, value: ETHER, trace: "1") ]
    )

    transfer, fee = result.rows
    assert_equal [ "3.0", ROUTER ], [ transfer.amount, transfer.counterparty ]
    assert_equal "fee", fee.kind
  end

  test "a token transfer or approval yields only its fee" do
    result = scan(normal: [ normal_tx("a", from: WALLET, to: ROUTER, value: 0) ])

    assert_equal [ [ "fee", "-0.00042" ] ], result.rows.map { |row| [ row.kind, row.amount ] }
  end

  test "a send to itself yields only its fee" do
    result = scan(normal: [ normal_tx("a", from: WALLET, to: WALLET, value: ETHER) ])

    assert_equal [ "fee" ], result.rows.map(&:kind)
  end

  test "a contract deployment names the created contract" do
    result = scan(normal: [ normal_tx("a", from: WALLET, to: nil, value: ETHER, contract_address: ROUTER) ])

    assert_equal ROUTER, result.rows.first.counterparty
  end

  test "a deployment with value is not counted twice when the explorer repeats its root trace" do
    result = scan(
      normal: [ normal_tx("a", from: WALLET, to: nil, value: ETHER, contract_address: ROUTER) ],
      # Blockscout lists the top-level create trace in the internal list too.
      internal: [ internal_tx("a", from: WALLET, to: ROUTER, value: ETHER) ]
    )

    transfer, fee = result.rows
    assert_equal [ "-1.0", ROUTER ], [ transfer.amount, transfer.counterparty ]
    assert_equal "fee", fee.kind
    assert_equal "-1.00042", result.balance
  end

  test "a deployment's root trace is dropped only once" do
    result = scan(
      normal: [ normal_tx("a", from: PAYER, to: nil, value: ETHER, contract_address: WALLET) ],
      internal: [ internal_tx("a", from: PAYER, to: WALLET, value: ETHER), internal_tx("a", from: PAYER, to: WALLET, value: ETHER, trace: "1") ]
    )

    assert_equal "2.0", result.balance, "a second, distinct transfer of the same value still counts"
  end

  test "a tracked contract is credited the value it was deployed with" do
    result = scan(normal: [ normal_tx("a", from: PAYER, to: nil, value: 2 * ETHER, contract_address: WALLET) ])

    row = result.rows.sole
    assert_equal [ "transfer", "2.0", PAYER ], [ row.kind, row.amount, row.counterparty ]
  end

  test "rows short of finality are unconfirmed and left out of the balance" do
    result = scan(normal: [
      normal_tx("a", from: PAYER, to: WALLET, value: ETHER, block: TIP - Blockchain::Ethereum::Scanner::FINALITY_DEPTH + 1),
      normal_tx("b", from: PAYER, to: WALLET, value: ETHER, block: TIP - Blockchain::Ethereum::Scanner::FINALITY_DEPTH + 2)
    ])

    assert_equal [ true, false ], result.rows.map(&:confirmed)
    assert_equal "1.0", result.balance
  end

  test "a chain balance the history explains raises no warning" do
    result = scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: ETHER) ], chain_balance: ETHER)

    assert_nil result.warning
  end

  test "a chain balance the history does not explain is a warning" do
    # e.g. 0.5 ETH of staking withdrawals, which no transaction list shows
    result = scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: ETHER) ], chain_balance: ETHER + ETHER / 2)

    assert_equal "1.0", result.balance, "the balance stays what the history adds up to"
    assert result.warning.start_with?(Blockchain::Ethereum::Scanner::BALANCE_MISMATCH_PREFIX)
    assert_includes result.warning, "the chain reports 1.5 ETH but the imported history adds up to 1.0 ETH (0.5 ETH unexplained)"
  end

  test "the comparison waits while any row is unconfirmed" do
    recent = TIP - Blockchain::Ethereum::Scanner::FINALITY_DEPTH + 2
    result = scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: ETHER, block: recent) ], chain_balance: ETHER)

    assert_nil result.warning, "the node already counts the unconfirmed row; the history total does not yet"
  end

  test "keeps every wei" do
    result = scan(normal: [ normal_tx("a", from: PAYER, to: WALLET, value: ETHER + 1) ])

    assert_equal "1.000000000000000001", result.rows.sole.amount
  end

  test "an unused address reports no activity" do
    result = scan

    assert_empty result.rows
    assert_equal "0.0", result.balance
    assert_equal 0, result.used_addresses
  end

  test "reads the connection's address" do
    client = FakeClient.new([ normal_tx("a", from: PAYER, to: WALLET, value: ETHER) ], [], TIP)

    result = Blockchain::Ethereum::Scanner.call(blockchain_connections(:eth_wallet), client: client)

    assert_equal "1.0", result.balance
  end

  private

    def scan(normal: [], internal: [], chain_balance: nil)
      Blockchain::Ethereum::Scanner.new(WALLET, FakeClient.new(normal, internal, TIP, chain_balance)).call
    end

    def tx_hash(seed)
      "0x#{seed * 64}"
    end

    def normal_tx(seed, from:, to:, value:, failed: false, block: 1_000, contract_address: nil)
      { hash: tx_hash(seed), from: from, to: to, value: value, fee: FEE, failed: failed, block_number: block,
        timestamp: Time.zone.at(1_700_000_000 + block), contract_address: contract_address }
    end

    def internal_tx(seed, from:, to:, value:, failed: false, block: 1_000, trace: "0")
      { hash: tx_hash(seed), trace_id: trace, from: from, to: to, value: value, failed: failed, block_number: block,
        timestamp: Time.zone.at(1_700_000_000 + block) }
    end
end
