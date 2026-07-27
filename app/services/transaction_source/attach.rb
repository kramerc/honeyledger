class TransactionSource::Attach
  class MismatchedTransaction < StandardError; end

  def self.call(transaction:, sourceable:, direction_overridden: false)
    new(transaction: transaction, sourceable: sourceable, direction_overridden: direction_overridden).call
  end

  def initialize(transaction:, sourceable:, direction_overridden: false)
    @transaction = transaction
    @sourceable = sourceable
    @direction_overridden = direction_overridden
  end

  # Idempotent on (sourceable_type, sourceable_id): returns the existing
  # TransactionSource if one already exists for the same ledger transaction.
  # Raises MismatchedTransaction if a row exists pointing to a *different*
  # ledger transaction — fail loudly rather than silently leave the legacy
  # sourceable_* columns and the join row pointing at different ledger
  # transactions, since transactions.sourceable still has no unique index.
  #
  # direction_overridden records how the importer interpreted this source row at
  # attach time (#222) and is written on create only — on the idempotent find path
  # the row already carries the value its first writer computed. It is a historical
  # fact about the import decision, not a re-derivation, so a later resync (which
  # never re-derives src/dest anyway) must not rewrite it.
  def call
    row = TransactionSource.create_or_find_by!(
      sourceable_type: @sourceable.class.name,
      sourceable_id: @sourceable.id
    ) do |new_row|
      new_row.ledger_transaction = @transaction
      new_row.direction_overridden = @direction_overridden
    end

    if row.transaction_id != @transaction.id
      raise MismatchedTransaction,
        "TransactionSource for #{@sourceable.class.name}##{@sourceable.id} " \
        "already belongs to transaction #{row.transaction_id}, refusing to attach to #{@transaction.id}"
    end

    row
  end
end
