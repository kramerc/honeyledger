class TransactionSource::Attach
  def self.call(transaction:, sourceable:)
    new(transaction: transaction, sourceable: sourceable).call
  end

  def initialize(transaction:, sourceable:)
    @transaction = transaction
    @sourceable = sourceable
  end

  # Idempotent: returns the existing TransactionSource if one already exists for this
  # (sourceable_type, sourceable_id) pair, otherwise creates a new join row.
  def call
    TransactionSource.create_or_find_by!(
      sourceable_type: @sourceable.class.name,
      sourceable_id: @sourceable.id
    ) do |row|
      row.ledger_transaction = @transaction
    end
  end
end
