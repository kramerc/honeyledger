class Transaction::AdoptOrphan
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(ledger_account:, amount_minor:, currency_id:, transacted_at:, description:, sourceable_type:, aggregator_account_class:)
    @ledger_account = ledger_account
    @amount_minor = amount_minor
    @currency_id = currency_id
    @transacted_at = transacted_at
    @description = description
    @sourceable_type = sourceable_type
    @aggregator_account_class = aggregator_account_class
  end

  def call
    candidates = candidate_query.limit(2).to_a
    candidates.size == 1 ? candidates.first : nil
  end

  private

    def candidate_query
      Transaction
        .where(user_id: @ledger_account.user_id)
        .where("transactions.src_account_id = :id OR transactions.dest_account_id = :id", id: @ledger_account.id)
        .where(amount_minor: @amount_minor, currency_id: @currency_id)
        .where(transacted_at: @transacted_at.beginning_of_day..@transacted_at.end_of_day)
        .where(description: @description)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(merged_into_id: nil, fx_amount_minor: nil)
        .where.missing(:merged_sources)
        .where(
          "transactions.sourceable_id IS NULL
           OR (transactions.sourceable_type = ? AND transactions.sourceable_id IN (?))",
          @sourceable_type, stale_aggregator_transaction_ids.presence || [ 0 ]
        )
    end

    def stale_aggregator_transaction_ids
      aggregator_transaction_class
        .joins(:account)
        .where(account: @aggregator_account_class.where.missing(:ledger_account))
        .pluck(:id)
    end

    def aggregator_transaction_class
      @sourceable_type.constantize
    end
end
