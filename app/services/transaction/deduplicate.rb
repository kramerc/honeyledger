# Collapses two or more ledger transactions that record the *same* real-world
# event (same bank account, same side, equal amount) into a single surviving
# row. Each loser's transaction_sources are moved onto the survivor and the
# loser is destroyed — producing the exact one-row-owns-all-sources shape that
# Transaction::Reconcile produces automatically at import time.
#
# This is the manual counterpart to import-time reconciliation, and is the
# opposite shape from Transaction::Merge (which combines a withdrawal + deposit
# on two different accounts into one transfer). It is intentionally irreversible
# — like Reconcile — so the controller gates it behind a confirmation panel.
class Transaction::Deduplicate
  attr_reader :survivor, :errors

  def initialize(*transactions, user:, survivor: nil)
    @transactions = transactions.flatten
    @user = user
    @survivor = survivor
    @errors = []
  end

  def call
    validate!
    return false if @errors.any?

    @survivor ||= heuristic_survivor
    losers = @transactions - [ @survivor ]

    ActiveRecord::Base.transaction do
      losers.each do |loser|
        # Move each source onto the survivor by reassigning the join row. We
        # can't use TransactionSource::Attach here — it refuses to move a row
        # that already points at another transaction. The unique index on
        # (sourceable_type, sourceable_id) guarantees the survivor can't already
        # own the same sourceable, so the reassignment never collides.
        loser.transaction_sources.to_a.each do |source|
          source.update!(ledger_transaction: @survivor)
        end

        # Reload so the now-stale cached transaction_sources association doesn't
        # cascade-destroy the rows we just moved. Destroying the loser reverses
        # its posting (after_destroy), removing the double-count.
        loser.reload
        loser.destroy!
      end
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @errors << e.message
    false
  end

  private

    def validate!
      if @transactions.size < 2
        @errors << "Select at least two transactions to combine"
        return
      end

      unless @transactions.all? { |t| t.user_id == @user.id }
        @errors << "All transactions must belong to you"
      end

      unless @transactions.map(&:amount_minor).uniq.size == 1
        @errors << "Amounts must match"
      end

      unless @transactions.map(&:currency_id).uniq.size == 1
        @errors << "Currencies must match"
      end

      if @transactions.any? { |t| t.has_fx? }
        @errors << "Foreign exchange transactions cannot be combined"
      end

      if @transactions.any?(&:opening_balance?)
        @errors << "Opening balance transactions cannot be combined"
      end

      if @transactions.any? { |t| t.split? || t.parent_transaction_id? }
        @errors << "Split transactions cannot be combined"
      end

      if @transactions.any?(&:excluded?)
        @errors << "Excluded transactions cannot be combined"
      end

      if @transactions.any? { |t| t.merged_into_id? || t.merged_sources.any? }
        @errors << "Merged transactions cannot be combined"
      end

      if @transactions.any? { |t| transfer?(t) }
        @errors << "Transfers cannot be combined as duplicates"
      end

      unless same_bank_side?
        @errors << "All transactions must use the same bank account on the same side"
      end

      if @survivor && @transactions.exclude?(@survivor)
        @errors << "The transaction to keep must be one of the selected transactions"
      end
    end

    # A non-transfer has exactly one balance-sheet side.
    def transfer?(transaction)
      transaction.src_account.balance_sheet? && transaction.dest_account.balance_sheet?
    end

    # True when every transaction is a non-transfer sharing the same
    # balance-sheet account on the same side (all src == BankX, or all dest ==
    # BankX) — the shape of duplicate recordings of one event.
    def same_bank_side?
      return false if @transactions.any? { |t| transfer?(t) }

      all_src = @transactions.all? { |t| t.src_account.balance_sheet? }
      all_dest = @transactions.all? { |t| t.dest_account.balance_sheet? }

      if all_src
        @transactions.map(&:src_account_id).uniq.size == 1
      elsif all_dest
        @transactions.map(&:dest_account_id).uniq.size == 1
      else
        false
      end
    end

    # Prefer a user-curated (categorized) row; tie-break by oldest.
    def heuristic_survivor
      @transactions.min_by { |t| [ t.category_id ? 0 : 1, t.transacted_at, t.created_at, t.id ] }
    end
end
