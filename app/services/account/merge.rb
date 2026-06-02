class Account::Merge
  attr_reader :target, :errors

  def initialize(target:, sources:, user:)
    @target  = target
    @sources = Array(sources).reject { |source| source.id == target&.id }
    @user    = user
    @errors  = []
  end

  def call
    validate!
    return false if @errors.any?

    source_ids = @sources.map(&:id)

    ActiveRecord::Base.transaction do
      # Repoint every transaction off the source accounts onto the target. update_all skips the
      # balance-maintenance callbacks (Transaction#transfer_account_balances), so we recompute
      # the target's balance from scratch below. Excluded and already-merged rows (amount_minor
      # 0) are moved too, so the sources end up truly empty and destroy! won't trip
      # restrict_with_error.
      Transaction.where(src_account_id: source_ids).update_all(src_account_id: @target.id)
      Transaction.where(dest_account_id: source_ids).update_all(dest_account_id: @target.id)

      # Preserve the user's existing import rules: move any pointing at a soon-to-be-deleted
      # account onto the kept account, otherwise dependent: :destroy would silently drop them.
      # The (user_id, match_type, lower(match_pattern)) unique index excludes account_id, so
      # repointing can never collide.
      @user.import_rules.where(account_id: source_ids).update_all(account_id: @target.id)

      # Only the target's balance changes: every moved transaction keeps its balance-sheet
      # counterpart (and per-row amount) on the other side, so those balances stay correct.
      @target.reset_balance

      @sources.each(&:destroy!)
    end

    # reset_balance uses update_column, so broadcast the refreshed balance to the sidebar.
    # The source removals broadcast on their own after_destroy_commit.
    @target.broadcast_sidebar_update
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    @errors << e.message
    false
  end

  private

    def validate!
      @errors << "Select a target account to keep" if @target.nil?
      @errors << "Select at least one other account to merge" if @sources.empty?

      accounts = [ @target, *@sources ].compact
      unless accounts.all? { |account| account.user_id == @user.id }
        @errors << "All accounts must belong to you"
      end

      kinds = accounts.map(&:kind).uniq
      unless kinds.size == 1 && %w[ expense revenue ].include?(kinds.first)
        @errors << "Only expense or revenue accounts of the same kind can be merged"
      end

      if accounts.map(&:currency_id).uniq.size > 1
        @errors << "All accounts must use the same currency"
      end
    end
end
