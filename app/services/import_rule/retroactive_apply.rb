class ImportRule::RetroactiveApply
  Change = Struct.new(:transaction, :old_account, :new_account, :direction, keyword_init: true)

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
        if change.direction == :expense
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

        changes << Change.new(
          transaction: transaction,
          old_account: counterpart,
          new_account: rule.account,
          direction: direction
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

    def rule_scope
      @rule_scope ||= if @rule
        @user.import_rules.where(id: @rule.id)
      else
        @user.import_rules
      end
    end
end
