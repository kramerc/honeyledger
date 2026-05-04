class AccountSource::Attach
  class MismatchedAccount < StandardError; end

  def self.call(account:, sourceable:)
    new(account: account, sourceable: sourceable).call
  end

  def initialize(account:, sourceable:)
    @account = account
    @sourceable = sourceable
  end

  # Idempotent on (sourceable_type, sourceable_id): returns the existing
  # AccountSource if one already exists for the same ledger account.
  # Raises MismatchedAccount if a row exists pointing to a *different*
  # ledger account — symmetric with TransactionSource::Attach.
  def call
    row = AccountSource.create_or_find_by!(
      sourceable_type: @sourceable.class.name,
      sourceable_id: @sourceable.id
    ) do |new_row|
      new_row.account = @account
    end

    if row.account_id != @account.id
      raise MismatchedAccount,
        "AccountSource for #{@sourceable.class.name}##{@sourceable.id} " \
        "already belongs to account #{row.account_id}, refusing to attach to #{@account.id}"
    end

    row
  end
end
