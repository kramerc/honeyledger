# Decides which side of the ledger transaction the linked bank account lands on for
# one incoming aggregator row.
#
# The default is the sign rule the importers have always used: a negative amount is
# money leaving the account (ledger on src), non-negative is money arriving (ledger
# on dest).
#
# One override sits on top of it. A SimpleFIN institution signs *both* legs of an
# internal transfer negative — the receiving account reports "TRANSFERRED FROM …" at
# a negative amount, which money cannot do (#222). The description is the only
# direction signal that feed provides (`extra` is null on every affected row), so we
# key on TRANSFER…FROM adjacency and flip the direction only.
#
# Two deliberate properties:
#
#   * Only the direction is overridden, never the amount. Simplefin::Transaction and
#     Lunchflow::Transaction stay verbatim mirrors of what the provider sent, and the
#     importers already store the ledger amount as `.abs`.
#   * The override is gated on `negative?`, so it is inert for feeds that are already
#     signed correctly and self-heals the moment the provider fixes their signing —
#     nothing to revert, and no window where the correction double-applies.
class Transaction::InferLedgerSide
  # Adjacency, not a fixed string: one observed row puts the counterparty token
  # directly after FROM with no intervening phrase, and the same feed also emits the
  # un-suffixed "TRANSFER FROM" form.
  INBOUND_TRANSFER_PATTERN = /\bTRANSFER(?:RED)?\s+FROM\b/i

  Result = Struct.new(:ledger_side, :direction_overridden, keyword_init: true) do
    def direction_overridden? = direction_overridden
  end

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # description:  the resolved description the importer will store — Lunch Flow
  #               prefers `merchant` over `description`, so the caller passes the
  #               resolved string rather than the source record.
  # amount_minor: the source row's signed minor amount.
  def initialize(description:, amount_minor:)
    @description = description
    @amount_minor = amount_minor
  end

  # Returns a Result carrying both the side and whether the override fired, so a
  # caller cannot derive the two inconsistently from separate regex evaluations.
  def call
    return Result.new(ledger_side: :dest, direction_overridden: true) if inbound_transfer?

    Result.new(ledger_side: @amount_minor.negative? ? :src : :dest, direction_overridden: false)
  end

  private

    # Regexp#match? is false for a nil description, so no separate blank guard is
    # needed. A nil amount_minor still raises, exactly as the sign rule did before.
    def inbound_transfer?
      @amount_minor.negative? && INBOUND_TRANSFER_PATTERN.match?(@description)
    end
end
