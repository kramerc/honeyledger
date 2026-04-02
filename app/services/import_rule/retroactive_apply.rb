class ImportRule::RetroactiveApply
  BALANCE_SHEET_KINDS = Transaction::Merge::BALANCE_SHEET_KINDS

  Change = Struct.new(:transaction, :old_account, :new_account, :direction, :merge_candidate, keyword_init: true)

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
        if balance_sheet_account?(change.new_account)
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
        next if rule.account_id == counterpart.id

        merge_candidate = if balance_sheet_account?(rule.account)
          find_merge_candidate(transaction, rule.account)
        end

        changes << Change.new(
          transaction: transaction,
          old_account: counterpart,
          new_account: rule.account,
          direction: direction,
          merge_candidate: merge_candidate
        )
      end

      changes
    end

    def candidate_transactions
      @user.transactions
        .where.not(sourceable_type: nil)
        .where(merged_into_id: nil, split: false, opening_balance: false, parent_transaction_id: nil)
        .includes(:src_account, :dest_account)
    end

    def identify_counterpart(transaction)
      src_linked = transaction.src_account.sourceable_id.present?
      dest_linked = transaction.dest_account.sourceable_id.present?

      if src_linked && !dest_linked
        [ :expense, transaction.dest_account ]
      elsif dest_linked && !src_linked
        [ :revenue, transaction.src_account ]
      end
    end

    def find_matching_rule(description)
      @rule_cache ||= {}
      normalized = description.to_s.strip.downcase
      return @rule_cache[normalized] if @rule_cache.key?(normalized)

      @rule_cache[normalized] = rule_scope.for_description(description).first
    end

    def find_merge_candidate(transaction, rule_account)
      candidates = @user.transactions
        .unmerged
        .includes(:src_account, :dest_account)
        .where.not(id: transaction.id)
        .where(amount_minor: transaction.amount_minor, currency_id: transaction.currency_id)
        .where(opening_balance: false, split: false)
        .where("src_account_id = :id OR dest_account_id = :id", id: rule_account.id)
        .where(transacted_at: (transaction.transacted_at - 7.days)..(transaction.transacted_at + 7.days))
        .to_a
        .select { |t| !balance_sheet_account?(t.src_account) || !balance_sheet_account?(t.dest_account) }
        .reject { |t| t.merged_sources.exists? }

      candidates.size == 1 ? candidates.first : nil
    end

    def balance_sheet_account?(account)
      BALANCE_SHEET_KINDS.include?(account.kind)
    end

    def rule_scope
      @rule_scope ||= if @rule
        @user.import_rules.where(id: @rule.id)
      else
        @user.import_rules
      end
    end
end
