class AccountSource::Attach
  def self.call(account:, sourceable:)
    new(account: account, sourceable: sourceable).call
  end

  def initialize(account:, sourceable:)
    @account = account
    @sourceable = sourceable
  end

  # Idempotent: returns the existing AccountSource if one already exists for this
  # (sourceable_type, sourceable_id) pair, otherwise creates a new join row.
  def call
    AccountSource.create_or_find_by!(
      sourceable_type: @sourceable.class.name,
      sourceable_id: @sourceable.id
    ) do |row|
      row.account = @account
    end
  end
end
