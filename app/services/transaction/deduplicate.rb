# Collapses two or more ledger transactions that record the *same* real-world
# event (same bank account, same side, equal amount) into a single surviving
# row. Each loser's transaction_sources are moved onto the survivor and the
# loser is destroyed — producing the exact one-row-owns-all-sources shape that
# Transaction::Reconcile produces automatically at import time.
#
# The selection may include at most one transfer (both sides balance-sheet),
# which is then always the survivor: it carries the richer state — the
# counterpart account and, for a merge result, the merged_sources chain. A
# merge result is created sourceless (its provenance lives on the zeroed
# originals) and Transaction::Unmerge destroys it, so absorbed sources are
# parked on the merged origin that shares the bank side rather than on the
# transfer itself; a plain transfer takes them directly.
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
    target = source_target
    if target.nil?
      @errors << "The transfer has no original on the shared bank account to keep the sources"
      return false
    end

    losers = @transactions - [ @survivor ]

    ActiveRecord::Base.transaction do
      losers.each do |loser|
        # Move each source by reassigning the join row. We can't use
        # TransactionSource::Attach here — it refuses to move a row that
        # already points at another transaction. The unique index on
        # (sourceable_type, sourceable_id) guarantees the target can't already
        # own the same sourceable, so the reassignment never collides.
        loser.transaction_sources.to_a.each do |source|
          source.update!(ledger_transaction: target)
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

      unless @transactions.all? { |transaction| transaction.user_id == @user.id }
        @errors << "All transactions must belong to you"
      end

      unless @transactions.map(&:amount_minor).uniq.size == 1
        @errors << "Amounts must match"
      end

      unless @transactions.map(&:currency_id).uniq.size == 1
        @errors << "Currencies must match"
      end

      if @transactions.any? { |transaction| transaction.has_fx? }
        @errors << "Foreign exchange transactions cannot be combined"
      end

      if @transactions.any?(&:opening_balance?)
        @errors << "Opening balance transactions cannot be combined"
      end

      if @transactions.any? { |transaction| transaction.split? || transaction.parent_transaction_id? }
        @errors << "Split transactions cannot be combined"
      end

      if @transactions.any?(&:excluded?)
        @errors << "Excluded transactions cannot be combined"
      end

      # Any row already folded into a merge, or a one-sided row that is itself
      # a merge result, is off limits; only the surviving transfer may be a
      # merge result.
      if @transactions.any? { |transaction| transaction.merged_into_id? } ||
         one_sided.any? { |transaction| transaction.merged_sources.any? }
        @errors << "Merged transactions cannot be combined"
      end

      if transfers.size > 1
        @errors << "Select at most one transfer to combine into"
      end

      unless same_bank_side?
        @errors << "All transactions must use the same bank account on the same side"
      end

      if @survivor && @transactions.exclude?(@survivor)
        @errors << "The transaction to keep must be one of the selected transactions"
      elsif @survivor && transfer && @survivor != transfer
        @errors << "The transfer must be the transaction to keep"
      end
    end

    # A non-transfer has exactly one balance-sheet side.
    def transfer?(transaction)
      transaction.src_account.balance_sheet? && transaction.dest_account.balance_sheet?
    end

    def transfers
      @transfers ||= @transactions.select { |transaction| transfer?(transaction) }
    end

    def transfer
      transfers.first if transfers.size == 1
    end

    def one_sided
      @one_sided ||= @transactions - transfers
    end

    # The side (:src or :dest) on which every one-sided row touches the bank,
    # or nil when they disagree or there are none.
    def bank_side
      return @bank_side if defined?(@bank_side)

      @bank_side =
        if one_sided.any? && one_sided.all? { |transaction| transaction.src_account.balance_sheet? }
          :src
        elsif one_sided.any? && one_sided.all? { |transaction| transaction.dest_account.balance_sheet? }
          :dest
        end
    end

    def bank_account_id
      return nil unless bank_side

      ids = one_sided.map { |transaction| transaction.public_send("#{bank_side}_account_id") }.uniq
      ids.first if ids.size == 1
    end

    # True when the one-sided rows share the same balance-sheet account on the
    # same side (all src == BankX, or all dest == BankX) — the shape of
    # duplicate recordings of one event — and any transfer touches that same
    # account on that same side.
    def same_bank_side?
      return false if bank_account_id.nil?

      transfers.all? { |transaction| transaction.public_send("#{bank_side}_account_id") == bank_account_id }
    end

    # Where the losers' sources land: a merge result hands them to the origin
    # that keeps the bank side, so Transaction::Unmerge restores them intact.
    def source_target
      return @survivor unless transfer?(@survivor) && @survivor.merged_sources.any?

      @survivor.merged_sources.find { |origin| origin.public_send("#{bank_side}_account_id") == bank_account_id }
    end

    # A transfer always survives. Otherwise prefer a user-curated (categorized)
    # row; tie-break by oldest.
    def heuristic_survivor
      transfer || @transactions.min_by { |transaction| [ transaction.category_id ? 0 : 1, transaction.transacted_at, transaction.created_at, transaction.id ] }
    end
end
