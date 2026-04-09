class Transaction::Unexclude
  attr_reader :errors

  def initialize(transaction, user:)
    @transaction = transaction
    @user = user
    @errors = []
  end

  def call
    validate!
    return false if @errors.any?

    ActiveRecord::Base.transaction do
      apply_account_balances
      @transaction.update!(excluded_at: nil)
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

      unless @transaction.excluded?
        @errors << "Transaction is not excluded"
      end
    end

    def apply_account_balances
      src_amount = @transaction.fx_amount_minor.nil? ? @transaction.amount_minor : @transaction.fx_amount_minor

      Account.update_counters(@transaction.src_account_id, balance_minor: -src_amount) if @transaction.src_account&.real?
      Account.update_counters(@transaction.dest_account_id, balance_minor: @transaction.amount_minor) if @transaction.dest_account&.real?
    end
end
