class Transaction::Unmerge
  attr_reader :restored_transactions, :errors

  def initialize(transaction, user:)
    @transaction = transaction
    @user = user
    @errors = []
    @restored_transactions = []
  end

  def call
    validate!
    return false if @errors.any?

    ActiveRecord::Base.transaction do
      originals = @transaction.merged_sources.to_a
      amount_minor = @transaction.amount_minor

      # Restore original amounts and clear merged_into_id.
      # The originals still have their original src/dest accounts intact.
      originals.each do |original|
        original.update!(amount_minor: amount_minor, merged_into_id: nil)
      end

      @restored_transactions = originals

      # Destroy the merged transfer (fires reverse_account_balances)
      @transaction.destroy!
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @errors << e.message
    false
  end

  private

    def validate!
      unless @transaction.user_id == @user.id
        @errors << "Transaction must belong to you"
      end

      if @transaction.merged_sources.empty?
        @errors << "Transaction has no merged sources to restore"
      end
    end
end
