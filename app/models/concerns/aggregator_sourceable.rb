# = AggregatorSourceable
#
# Shared behaviour for the raw aggregator transaction mirrors (Simplefin::Transaction,
# Lunchflow::Transaction): how one incoming row will be posted to the ledger.
#
# The direction rule itself lives in Transaction::InferLedgerSide. This concern is the
# single place that feeds it, so an importer and a balance walk-back cannot answer
# "which way does this row go?" differently.
#
# Including models must define +resolved_description+ — the string the importer will
# store, which is not always the +description+ column (Lunch Flow prefers +merchant+).
module AggregatorSourceable
  extend ActiveSupport::Concern

  # The side of the ledger transaction this row's account lands on, plus whether the
  # inbound-transfer override fired. See Transaction::InferLedgerSide.
  def ledger_direction
    Transaction::InferLedgerSide.call(
      description: resolved_description,
      amount_minor: amount_minor
    )
  end

  # This row's contribution to the ledger balance, signed by the direction the importer
  # will actually post it in rather than by the provider's sign.
  #
  # The importers store amount_minor.abs and let src/dest carry the direction (#222), so
  # a balance reconstructed from the raw feed sign disagrees with the ledger by twice the
  # amount of every overridden row (#227).
  def signed_ledger_amount
    row_amount = amount.to_d
    # amount_minor is nil when the provider sent no amount (or no currency is resolvable);
    # InferLedgerSide would raise on nil.negative?, and nil.to_d is 0, so there is no sign
    # to apply.
    return row_amount if amount_minor.nil?

    ledger_direction.ledger_side == :dest ? row_amount.abs : -row_amount.abs
  end
end
