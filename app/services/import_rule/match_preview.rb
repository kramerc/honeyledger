# Live "matches in your ledger" preview for the rule editor. Given a draft pattern +
# match type (and the draft's target account / exclude flag), finds the user's existing
# transactions whose description matches — using the SAME escaped, case-insensitive LIKE
# semantics as ImportRule#for_description, but transaction-side (the pattern is the bound
# literal and `description` is the column). Whether each match "would move" is decided by
# the SAME change_for logic the retroactive apply uses, so the editor preview and the
# Preview modal agree. Unlike the apply, the list also includes already-excluded rows so
# you can see everything the pattern matches.
class ImportRule::MatchPreview
  include ImportRule::TransactionScope

  LIMIT = 50

  Match = Struct.new(:transaction, :direction, :current_account, :would_move, :new_account, :excluded, keyword_init: true)

  attr_reader :target_account, :pattern, :match_type

  def initialize(user:, pattern:, match_type: "contains", account_id: nil, exclude: false)
    @user = user
    @pattern = pattern.to_s.strip
    @match_type = ImportRule.match_types.key?(match_type.to_s) ? match_type.to_s : "contains"
    @exclude = ActiveModel::Type::Boolean.new.cast(exclude) || false
    @target_account = account_id.present? && !@exclude ? @user.accounts.find_by(id: account_id) : nil
    @draft = @user.import_rules.build(match_pattern: @pattern, match_type: @match_type, exclude: @exclude, account: @target_account)
    @matches = nil
    @has_more = false
  end

  def matches
    @matches ||= build_matches
  end

  def has_more?
    matches # ensure populated
    @has_more
  end

  def move_count
    matches.count(&:would_move)
  end

  # "N" or "N+" — when the result set is truncated the move count is only a lower bound of the
  # visible window (more movable rows may exist beyond the cap), so qualify it with "+". The
  # Preview modal (RetroactiveApply, unbounded) is the authoritative count.
  def move_count_summary
    return "#{move_count}+" if has_more?

    move_count.to_s
  end

  # Header badge, e.g. "2 matches" / "1 match" / "50+ matches".
  def count_summary
    return "#{LIMIT}+ matches" if has_more?

    "#{matches.size} #{"match".pluralize(matches.size)}"
  end

  def exclude? = @exclude

  private

    def build_matches
      return [] if @pattern.blank?

      rows = matched_transactions.limit(LIMIT + 1).to_a
      @has_more = rows.size > LIMIT

      rows.first(LIMIT).map { |transaction| build_match(transaction) }
    end

    def build_match(transaction)
      # Already-excluded rows still show (so you can see what the pattern catches), but they
      # wouldn't be touched by an apply.
      if transaction.excluded_at.present?
        return Match.new(transaction: transaction, direction: nil, current_account: nil,
                         would_move: false, new_account: nil, excluded: true)
      end

      direction, counterpart = identify_counterpart(transaction)
      change = change_for(transaction, @draft, direction: direction, counterpart: counterpart)

      # With a destination (account or exclude), "would move" is exactly what the apply would
      # do. Before an account is chosen, fall back to "any match with a known counterpart
      # could be reassigned once you pick one".
      would_move = if @exclude || @target_account
        change.present?
      else
        direction.present?
      end

      Match.new(
        transaction: transaction,
        direction: direction,
        current_account: would_move ? (change&.old_account || counterpart) : nil,
        would_move: would_move,
        new_account: change&.new_account,
        excluded: false
      )
    end

    def matched_transactions
      preview_transactions
        .where(like_clause, pattern: like_argument)
        # Non-excluded (actionable) rows first, so already-excluded rows can't push movable
        # rows out of the LIMIT window and undercount the footer; then most recent first.
        # (NULLS FIRST keeps it a plain column ref, which SELECT DISTINCT allows in ORDER BY.)
        .order(Arel.sql("transactions.excluded_at ASC NULLS FIRST"), transacted_at: :desc)
    end

    # Like candidate_transactions (RetroactiveApply's set) but keeps already-excluded rows,
    # so the editor preview shows everything the pattern matches — not only what would change.
    def preview_transactions
      @user.transactions
        .joins(:transaction_sources)
        .where(merged_into_id: nil, split: false, opening_balance: false, parent_transaction_id: nil)
        .includes(:currency, src_account: :account_sources, dest_account: :account_sources, transaction_sources: :sourceable)
        .distinct
    end

    # TRIM the column so the preview matches ImportRule#for_description / #matches?, which
    # strip the description before comparing (otherwise " FOO " disagrees on exact/ends_with).
    def like_clause
      case @match_type
      when "exact" then "LOWER(TRIM(transactions.description)) = :pattern"
      else "LOWER(TRIM(transactions.description)) LIKE :pattern ESCAPE '\\'"
      end
    end

    # The bound literal for the comparison: lowercased, with LIKE metacharacters escaped
    # (except for the exact match, which is a plain equality).
    def like_argument
      lowered = @pattern.downcase
      return lowered if @match_type == "exact"

      escaped = lowered.gsub(/[\\%_]/) { |char| "\\#{char}" }
      case @match_type
      when "starts_with" then "#{escaped}%"
      when "ends_with" then "%#{escaped}"
      else "%#{escaped}%" # contains
      end
    end
end
