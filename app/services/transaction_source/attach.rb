class TransactionSource::Attach
  class MismatchedTransaction < StandardError; end

  def self.call(transaction:, sourceable:)
    new(transaction: transaction, sourceable: sourceable).call
  end

  def initialize(transaction:, sourceable:)
    @transaction = transaction
    @sourceable = sourceable
  end

  # Idempotent on (sourceable_type, sourceable_id): returns the existing
  # TransactionSource if one already exists for the same ledger transaction.
  # Raises MismatchedTransaction if a row exists pointing to a *different*
  # ledger transaction — fail loudly rather than silently leave the legacy
  # sourceable_* columns and the join row pointing at different ledger
  # transactions, since transactions.sourceable still has no unique index.
  def call
    row = TransactionSource.create_or_find_by!(
      sourceable_type: @sourceable.class.name,
      sourceable_id: @sourceable.id
    ) do |new_row|
      new_row.ledger_transaction = @transaction
    end

    if row.transaction_id != @transaction.id
      raise MismatchedTransaction,
        "TransactionSource for #{@sourceable.class.name}##{@sourceable.id} " \
        "already belongs to transaction #{row.transaction_id}, refusing to attach to #{@transaction.id}"
    end

    row
  end
end
