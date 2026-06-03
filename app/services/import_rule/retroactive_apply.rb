class ImportRule::RetroactiveApply
  Change = Struct.new(:transaction, :old_account, :new_account, :direction, :merge_candidate, :action, keyword_init: true)

  attr_reader :changes, :errors

  def initialize(user:, rule: nil)
    @user = user
    @rule = rule
    @changes = []
    @errors = []
  end

  def preview
    @changes = compute_changes
  end

  def apply
    preview if @changes.empty?
    return 0 if @changes.empty?

    applied = 0
    ActiveRecord::Base.transaction do
      @changes.each do |change|
        if change.action == :exclude
          Transaction::Exclude.new(change.transaction, user: @user).call
        elsif change.new_account.balance_sheet?
          Transaction::AutoMerge.call(change.transaction, rule_account: change.new_account)
        elsif change.direction == :expense
          change.transaction.update!(dest_account: change.new_account)
        else
          change.transaction.update!(src_account: change.new_account)
        end
        applied += 1
      end
    end
    applied
  rescue ActiveRecord::ActiveRecordError => e
    @errors << e.message
    0
  end

  private

    def compute_changes
      changes = []

      candidate_transactions.find_each do |transaction|
        direction, counterpart = identify_counterpart(transaction)
        next unless direction

        rule = find_matching_rule(transaction.description)
        next unless rule

        if rule.exclude?
          changes << Change.new(
            transaction: transaction,
            old_account: counterpart,
            new_account: nil,
            direction: direction,
            merge_candidate: nil,
            action: :exclude
          )
          next
        end

        next if rule.account_id == counterpart.id

        merge_candidate = nil
        if rule.account.balance_sheet?
          candidates = merge_candidates(transaction, rule.account)
          # Ambiguous balance-sheet match: Transaction::AutoMerge leaves it untouched (#182),
          # so don't surface it as a reassignment that never resolves.
          next if candidates.size > 1

          merge_candidate = candidates.first
        end

        changes << Change.new(
          transaction: transaction,
          old_account: counterpart,
          new_account: rule.account,
          direction: direction,
          merge_candidate: merge_candidate,
          action: :reassign
        )
      end

      changes
    end

    def candidate_transactions
      @user.transactions
        .joins(:transaction_sources)
        .where(merged_into_id: nil, excluded_at: nil, split: false, opening_balance: false, parent_transaction_id: nil)
        .includes(src_account: :account_sources, dest_account: :account_sources, transaction_sources: :sourceable)
        .distinct
    end

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

    def find_matching_rule(description)
      @rule_cache ||= {}
      normalized = description.to_s.strip.downcase
      return @rule_cache[normalized] if @rule_cache.key?(normalized)

      @rule_cache[normalized] = rule_scope.for_description(description).first
    end

    # Non-transfer transactions involving rule_account that this transaction could merge with.
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
    end

    def rule_scope
      @rule_scope ||= if @rule
        @user.import_rules.where(id: @rule.id)
      else
        @user.import_rules
      end
    end
end
