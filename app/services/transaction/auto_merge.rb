class Transaction::AutoMerge
  def self.call(transaction, rule_account: nil)
    new(transaction, rule_account: rule_account).call
  end

  def initialize(transaction, rule_account: nil)
    @transaction = transaction
    @rule_account = rule_account
  end

  def call
    return if @transaction.merged_into_id? || @transaction.excluded? ||
              @transaction.opening_balance? ||
              @transaction.split? || @transaction.parent_transaction_id? ||
              @transaction.has_fx? || @transaction.amount_minor == 0 ||
              @transaction.merged_sources.exists?

    return absorb_into_existing_transfer unless @rule_account

    result = merge_with_counterpart
    # Ambiguous: 2+ equal-amount counterparts on the rule account — we can't tell which one
    # this transaction pairs with. Leave it untouched for manual review rather than fall
    # through to absorb_into_existing_transfer (which clones a transfer and double-counts a
    # still-live charge) or apply_rule_account (which reassigns arbitrarily). See #182.
    return if result == :ambiguous

    result || absorb_into_existing_transfer || apply_rule_account
  end

  private

    # Find a matching expense/revenue transaction involving the rule account and merge via Transaction::Merge.
    # Returns true if merged, :candidate_found if a candidate existed but merge failed, :ambiguous if 2+
    # candidates matched (can't safely pick one), false if no candidate.
    def merge_with_counterpart
      candidates = expense_revenue_candidates
      return false if candidates.empty?
      return :ambiguous if candidates.size > 1

      merger = Transaction::Merge.new(@transaction, candidates.first, user: @transaction.user)
      merger.call || :candidate_found
    end

    # Find an existing BS-to-BS transfer that this transaction duplicates and absorb into it
    def absorb_into_existing_transfer
      transfer = find_transfer_candidate
      return false unless transfer

      ActiveRecord::Base.transaction do
        merged = ::Transaction.create!(
          user: transfer.user,
          src_account: transfer.src_account,
          dest_account: transfer.dest_account,
          amount_minor: transfer.amount_minor,
          currency: transfer.currency,
          description: transfer.description,
          transacted_at: [ @transaction.transacted_at, transfer.transacted_at ].compact.min,
          cleared_at: [ @transaction.cleared_at, transfer.cleared_at ].compact.min
        )

        [ @transaction, transfer ].each do |t|
          t.update!(amount_minor: 0, fx_amount_minor: nil, fx_currency_id: nil, merged_into: merged)
        end
      end
      true
    end

    # No merge candidate found — apply the import rule's balance sheet account directly
    def apply_rule_account
      if @transaction.src_account.balance_sheet?
        @transaction.update!(dest_account: @rule_account)
      else
        @transaction.update!(src_account: @rule_account)
      end
    end

    # Expense/revenue (non-transfer) transactions involving the rule_account
    def expense_revenue_candidates
      base_candidates
        .where("transactions.src_account_id = :id OR transactions.dest_account_id = :id", id: @rule_account.id)
        .to_a
        .reject { |t| transfer?(t) }
    end

    # Find BS-to-BS transfers involving the same ledger account
    def find_transfer_candidate
      candidates = base_candidates
        .where("transactions.src_account_id = :id OR transactions.dest_account_id = :id", id: ledger_account_id)
        .to_a
        .select { |t| transfer?(t) }

      candidates.size == 1 ? candidates.first : nil
    end

    def base_candidates
      @transaction.user.transactions
        .unmerged
        .unexcluded
        .includes(:src_account, :dest_account)
        .where.not(id: @transaction.id)
        .where(amount_minor: @transaction.amount_minor, currency_id: @transaction.currency_id)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(fx_amount_minor: nil)
        .where.missing(:merged_sources)
        .where(transacted_at: date_range)
    end

    def ledger_account_id
      if @transaction.src_account.balance_sheet?
        @transaction.src_account_id
      else
        @transaction.dest_account_id
      end
    end

    def transfer?(transaction)
      transaction.src_account.balance_sheet? && transaction.dest_account.balance_sheet?
    end

    def date_range
      (@transaction.transacted_at - 7.days)..(@transaction.transacted_at + 7.days)
    end
end
