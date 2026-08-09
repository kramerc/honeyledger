class ImportRule::RetroactiveApply
  include ImportRule::TransactionScope

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

        change = change_for(transaction, rule, direction: direction, counterpart: counterpart)
        changes << change if change
      end

      changes
    end

    # When scoped to a single rule, match it in memory so an unsaved draft rule can be
    # previewed; otherwise resolve the winning rule across all of the user's rules.
    def find_matching_rule(description)
      @rule_cache ||= {}
      normalized = description.to_s.strip.downcase
      return @rule_cache[normalized] if @rule_cache.key?(normalized)

      @rule_cache[normalized] =
        if @rule
          @rule.matches?(description) ? @rule : nil
        else
          @user.import_rules.for_description(description).first
        end
    end
end
