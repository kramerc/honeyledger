require "test_helper"

class Blockchain::TransactionTest < ActiveSupport::TestCase
  test "describes receipts and sends with the full counterparty address" do
    assert_equal "Received from bc1q8c6fshw2dlwun7ekn9qwf37cu2rn755upcp6el", blockchain_transactions(:received).resolved_description
    assert_equal "Sent to bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g", blockchain_transactions(:sent).resolved_description
  end

  test "describes fees and rows without a counterparty by asset" do
    assert_equal "Bitcoin network fee", blockchain_transactions(:sent_fee).resolved_description

    coinbase = blockchain_transactions(:received).dup.tap { |row| row.counterparty = nil }
    assert_equal "Bitcoin received", coinbase.resolved_description

    outflow = blockchain_transactions(:sent).dup.tap { |row| row.counterparty = nil }
    assert_equal "Bitcoin sent", outflow.resolved_description
  end

  test "amount_minor is in satoshis and the direction follows the sign" do
    sent = blockchain_transactions(:sent)

    assert_equal(-450_000, sent.amount_minor)
    assert_equal :src, sent.ledger_direction.ledger_side
    assert_equal :dest, blockchain_transactions(:received).ledger_direction.ledger_side
    assert_not sent.ledger_direction.direction_overridden?
  end

  test "remote_id is unique per account" do
    duplicate = blockchain_transactions(:sent).dup

    assert_not duplicate.valid?
    assert duplicate.errors[:remote_id].any?
  end

  test "confirmed scope" do
    assert_includes Blockchain::Transaction.confirmed, blockchain_transactions(:sent)
  end
end
