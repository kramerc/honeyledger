# Shared transaction scoping, import-side detection, and per-transaction change
# computation for the import-rule services (ImportRule::RetroactiveApply and
# ImportRule::MatchPreview), so the live editor preview and the retroactive
# apply agree on what a rule would actually do. Expects an @user instance
# variable on the including object.
module ImportRule::TransactionScope
  Change = Struct.new(:transaction, :old_account, :new_account, :direction, :merge_candidate, :action, keyword_init: true)

  private

    # Imported, non-merged, non-split, non-excluded transactions that a rule could act on.
    def candidate_transactions
      @user.transactions
        .joins(:transaction_sources)
        .where(merged_into_id: nil, excluded_at: nil, split: false, opening_balance: false, parent_transaction_id: nil)
        .includes(:currency, src_account: :account_sources, dest_account: :account_sources, transaction_sources: :sourceable)
        .distinct
    end

    # The change a matching rule would make to a transaction, or nil if it would make none
    # (no identifiable import side, already in the target account, or an ambiguous balance-sheet
    # merge). `direction`/`counterpart` come from identify_counterpart.
    def change_for(transaction, rule, direction:, counterpart:)
      return nil unless direction && rule

      if rule.exclude?
        return Change.new(transaction: transaction, old_account: counterpart, new_account: nil,
                          direction: direction, merge_candidate: nil, action: :exclude)
      end

      return nil if rule.account.nil? # assign rule without a chosen account: no destination yet
      return nil if rule.account_id == counterpart.id

      merge_candidate = nil
      if rule.account.balance_sheet?
        candidates = merge_candidates(transaction, rule.account)
        # Ambiguous balance-sheet match (2+ mergeable counterparts): Transaction::AutoMerge
        # leaves it untouched (#182), so don't surface it as a reassignment that never resolves.
        return nil if candidates.size > 1

        merge_candidate = candidates.first
      end

      Change.new(transaction: transaction, old_account: counterpart, new_account: rule.account,
                 direction: direction, merge_candidate: merge_candidate, action: :reassign)
    end

    # Returns [direction, counterpart_account] where direction is :expense or :revenue and
    # counterpart is the non-import side (the account a rule would reassign). nil when the
    # import side can't be identified (e.g. both or neither side is linked).
    def identify_counterpart(transaction)
      source_account_ids = import_side_account_ids(transaction)
      src_linked = source_account_ids.include?(transaction.src_account_id)
      dest_linked = source_account_ids.include?(transaction.dest_account_id)

      if src_linked && !dest_linked
        [ :expense, transaction.dest_account ]
      elsif dest_linked && !src_linked
        [ :revenue, transaction.src_account ]
      end
    end

    # The ledger accounts that sit on the import side of a transaction. Aggregator
    # accounts (SimpleFIN, Lunch Flow) carry an AccountSource, so the import side is
    # whichever account is linked. CSV imports never create AccountSource records —
    # their import side is the Csv::Import's chosen ledger account, reached through
    # the transaction's Csv::Transaction source. Without this, CSV-sourced
    # transactions have no recognized counterpart and rules never match them.
    def import_side_account_ids(transaction)
      ids = []
      ids << transaction.src_account_id if transaction.src_account.account_sources.any?
      ids << transaction.dest_account_id if transaction.dest_account.account_sources.any?
      transaction.transaction_sources.each do |source|
        sourceable = source.sourceable
        # Read import_id off the already-preloaded Csv::Transaction and resolve the
        # account through a cached map, rather than walking sourceable.account
        # (import -> account) per row inside find_each.
        ids << csv_import_account_ids[sourceable.import_id] if sourceable.is_a?(Csv::Transaction)
      end
      ids.compact.uniq
    end

    # import_id => ledger account_id for this user's CSV imports, loaded once.
    def csv_import_account_ids
      @csv_import_account_ids ||= Csv::Import.where(user_id: @user.id).pluck(:id, :account_id).to_h
    end

    # Non-transfer transactions involving rule_account that this transaction could merge with.
    # Only opposite-side rows are real counterparts (mirrors Transaction::Merge); same-direction
    # rows can't form a transfer and so are not ambiguity.
    def merge_candidates(transaction, rule_account)
      @user.transactions
        .unmerged
        .unexcluded
        .includes(:src_account, :dest_account)
        .where.not(id: transaction.id)
        .where(amount_minor: transaction.amount_minor, currency_id: transaction.currency_id)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(fx_amount_minor: nil)
        .where("transactions.src_account_id = :id OR transactions.dest_account_id = :id", id: rule_account.id)
        .where(transacted_at: (transaction.transacted_at - 7.days)..(transaction.transacted_at + 7.days))
        .where.missing(:merged_sources)
        .to_a
        .select { |t| !t.src_account.balance_sheet? || !t.dest_account.balance_sheet? }
        .select { |candidate| mergeable?(transaction, candidate) }
    end

    # Mirrors Transaction::Merge: a candidate can merge into a transfer only when one side has a
    # balance-sheet account as source and the other as destination.
    def mergeable?(transaction, candidate)
      (transaction.src_account.balance_sheet? && candidate.dest_account.balance_sheet?) ||
        (candidate.src_account.balance_sheet? && transaction.dest_account.balance_sheet?)
    end
end
