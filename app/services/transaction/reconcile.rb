class Transaction::Reconcile
  # Aggregator-sourced candidates match within ±N days of the incoming date to
  # absorb the credit-card auth-vs-post skew (typically 1–2 days). Manual-entry
  # orphans keep the stricter same-day window (paired with their exact-description
  # rule, #117). Start at 3 and tune later (#158).
  RECONCILE_TRANSACTED_AT_WINDOW_DAYS = 3

  # Aggregators mask embedded digit runs differently, and masking happens mid-string, so
  # neither description is a prefix of the other and the raw prefix match fails on rows that
  # describe the same event (#221). Collapsing digit-or-X runs to a common token on both sides
  # makes them comparable again.
  #
  # Deliberately narrow, each part chosen against the descriptions actually in the ledger:
  #
  #   * Digits and X only. `*` never appears in a run of two or more — it shows up as a
  #     descriptor separator (letter-then-star), including on an imported card account, so
  #     there is no evidence of asterisk redaction to handle. `#` is a store-number marker
  #     (`#` followed by digits in nearly every occurrence), so folding it in would erase a
  #     character that legitimately distinguishes two stores.
  #   * Runs of two or more, never one. A lone digit is a real distinction: it keeps
  #     "PAYMENT 1" and "PAYMENT 2" apart.
  #   * `~` as the placeholder because it appears nowhere in any feed. `#` would be wrong
  #     here for the same reason it is excluded above — it occurs literally, so `A#B` would
  #     normalize onto `A12B`.
  #
  # One constant each, so widening the class later (an asterisk-masked card descriptor, say)
  # is a one-line change plus a test.
  MASKED_RUN_PATTERN = "[0-9x]{2,}"
  MASKED_RUN_PLACEHOLDER = "~"

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(ledger_account:, amount_minor:, currency_id:, transacted_at:, description:, ledger_side:, incoming_source: nil)
    raise ArgumentError, "ledger_side must be :src or :dest" unless %i[src dest].include?(ledger_side)

    @ledger_account = ledger_account
    @amount_minor = amount_minor
    @currency_id = currency_id
    @transacted_at = transacted_at
    @description = description
    @ledger_side = ledger_side
    @incoming_source = incoming_source
    @incoming_source_class = incoming_source&.class
  end

  def call
    return nil if @description.blank?

    # Abstain immediately if the live orphans alone are already ambiguous.
    live_candidates = candidate_query.limit(2).to_a
    return nil if live_candidates.size >= 2

    # The first aggregator's side may have been auto-merged into a transfer (zeroed,
    # merged_into set), which the live query can't see because it matches on
    # amount_minor. Consider live and merged candidates together so that a live +
    # merged collision within the widened window is treated as ambiguous rather than
    # silently attaching to the live row and hiding the merged event (#158).
    candidates = live_candidates + merged_candidate_query.limit(2).to_a
    candidates.size == 1 ? candidates.first : nil
  end

  private

    def candidate_query
      # Direction-aware: an incoming charge (ledger on src) must only match a
      # candidate with the ledger account on src, and a refund (ledger on dest)
      # only matches a dest candidate. Without this, an equal same-day
      # charge/refund pair shares amount/day/description and both match,
      # yielding size == 2 → nil → a duplicate ledger transaction (#159).
      account_column = @ledger_side == :src ? :src_account_id : :dest_account_id

      Transaction
        .where(user_id: @ledger_account.user_id)
        .where(account_column => @ledger_account.id)
        .where(amount_minor: @amount_minor, currency_id: @currency_id)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(merged_into_id: nil, fx_amount_minor: nil)
        .where.missing(:merged_sources)
        .where(orphan_with_description_clause)
    end

    # The incoming row's counterpart on the other aggregator may already have been
    # auto-merged into a transfer, so its original is zeroed (amount_minor 0) and
    # flagged merged_into_id. The live query matches on amount_minor and so can never
    # find it; here we match the real amount/currency on the surviving merge head
    # instead and attach the incoming source onto the zeroed original — keeping it a
    # sibling of the first aggregator's source so the head's badge shows both, and
    # dodging the resync hazard of attaching to the head (whose scalars a later resync
    # would overwrite). Csv::ImportTransactionsJob's find_merged_duplicate_target does
    # the same within a single aggregator. call evaluates this alongside the live query
    # every time so a live + merged collision within the window is caught as ambiguous.
    #
    # Only sourced merged originals qualify (sourced_clause requires a source): a
    # purely manual merged transaction is left untouched, matching the conservative
    # #117 stance and the issue's aggregator-A-then-B scenario. Within sourced_clause
    # only aggregator sources get the widened window, so this fires for the
    # SimpleFIN/Lunch Flow date-skew case it targets.
    def merged_candidate_query
      account_column = @ledger_side == :src ? :src_account_id : :dest_account_id

      Transaction
        .joins("INNER JOIN transactions heads ON heads.id = transactions.merged_into_id")
        .where(user_id: @ledger_account.user_id)
        .where(account_column => @ledger_account.id)
        .where("heads.amount_minor = ? AND heads.currency_id = ?", @amount_minor, @currency_id)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(fx_amount_minor: nil)
        .where.not(merged_into_id: nil)
        .where(sourced_clause)
    end

    # Manual-entry orphans (no transaction_sources rows) require an exact
    # case-insensitive description match — preserves #117 safety so a user's
    # manual placeholder cannot be scooped up by an unrelated long aggregator
    # description that happens to share a short prefix.
    #
    # Sourced orphans (some transaction_sources rows) use a bidirectional
    # case-insensitive prefix match — covers the cross-aggregator truncation case
    # (e.g. Lunch Flow's 32-char merchant truncation of a longer SimpleFIN
    # description). Candidates are excluded if they already have a *live* source of
    # the same aggregator type as the incoming source, since the incoming sft would
    # represent a separate real-world event.
    def orphan_with_description_clause
      manual_entry_clause.or(sourced_clause)
    end

    # Manual-entry orphans keep the same-day window paired with their exact-description
    # rule (#117).
    def manual_entry_clause
      table = Transaction.arel_table

      Arel::Nodes::Not.new(has_any_source_node)
        .and(same_day_window(table))
        .and(case_insensitive_eq(table[:description], @description))
    end

    def sourced_clause
      table = Transaction.arel_table
      ts_table = TransactionSource.arel_table

      has_any_source_node
        .and(sourced_date_window(table))
        .and(Arel::Nodes::Not.new(live_collision_subquery(ts_table)))
        .and(description_match(table[:description], @description))
    end

    # The normalized comparison is OR'd onto the raw one rather than replacing it, because it
    # is not strictly weaker: "PAY 1" is a raw prefix of "PAY 12" but normalizes to "pay 1"
    # vs "pay ~", which is not a prefix. Truncation can land mid-run, so the raw branch has to
    # survive for the case prefix_match was built for. OR-ing also makes #221 purely additive —
    # nothing that reconciles today can stop reconciling.
    #
    # Sourced candidates only. manual_entry_clause keeps its exact-match rule (#117): collapsing
    # digit runs would let a user's manual placeholder be scooped up by an aggregator row that
    # differs only in an account number.
    def description_match(column, value)
      prefix_match(column, value).or(normalized_prefix_match(column, value))
    end

    # Aggregator-sourced (SimpleFIN/Lunch Flow) candidates widen to ±N days to absorb
    # the credit-card auth-vs-post skew (#158); CSV- and any other-sourced candidates
    # keep the same-day window, since the date-skew problem is specific to bank feeds
    # and the issue scopes the wider window to aggregators. wide_window already
    # subsumes same_day_window, so an aggregator source effectively matches on the
    # wide window alone.
    def sourced_date_window(table)
      same_day_window(table).or(has_aggregator_source_node.and(wide_window(table)))
    end

    def has_any_source_node
      source_exists_node
    end

    def has_aggregator_source_node
      ts_table = TransactionSource.arel_table
      aggregator_type_names = AggregatorLinkable.registry.map { |account_class| account_class.transaction_class.name }

      source_exists_node(ts_table[:sourceable_type].in(aggregator_type_names))
    end

    def source_exists_node(extra_condition = nil)
      table = Transaction.arel_table
      ts_table = TransactionSource.arel_table

      subquery = ts_table.project(1).where(ts_table[:transaction_id].eq(table[:id]))
      subquery = subquery.where(extra_condition) if extra_condition
      Arel::Nodes::Exists.new(subquery)
    end

    def same_day_window(table)
      table[:transacted_at].between(@transacted_at.beginning_of_day..@transacted_at.end_of_day)
    end

    def wide_window(table)
      days = RECONCILE_TRANSACTED_AT_WINDOW_DAYS
      table[:transacted_at].between((@transacted_at - days.days).beginning_of_day..(@transacted_at + days.days).end_of_day)
    end

    # The candidate is disqualified if it already carries a *live* source. When the
    # caller supplies an incoming source, only same-aggregator-type collisions
    # disqualify (so cross-aggregator append is permitted). With no incoming
    # source, any live source disqualifies — that's the conservative fallback the
    # original AdoptOrphan applied.
    def live_collision_subquery(ts_table)
      live_pairs_clauses = AggregatorLinkable.registry.filter_map do |account_class|
        next if @incoming_source_class && account_class != incoming_account_class

        ts_table[:sourceable_type].eq(account_class.transaction_class.name)
          .and(ts_table[:sourceable_id].in(live_transactions_for(account_class).arel))
      end

      # Csv::Transaction isn't in AggregatorLinkable.registry (it has no
      # connection-style aggregator account). Two distinct rows in the same
      # Csv::Import are by definition different real-world events even when
      # amount/date/description coincide, so candidates already sourced by a
      # row from the same import must disqualify a CSV-incoming candidate from
      # being adopted. Cross-import CSV-on-CSV adoption is still allowed (e.g.
      # overlapping monthly statements).
      if @incoming_source.is_a?(Csv::Transaction) && @incoming_source.import_id.present?
        same_import_csv_ids = Csv::Transaction.where(import_id: @incoming_source.import_id).select(:id)
        live_pairs_clauses << ts_table[:sourceable_type].eq("Csv::Transaction")
          .and(ts_table[:sourceable_id].in(same_import_csv_ids.arel))
      end

      return Arel.sql("FALSE") if live_pairs_clauses.empty?

      Arel::Nodes::Exists.new(
        ts_table.project(1)
          .where(ts_table[:transaction_id].eq(Transaction.arel_table[:id]))
          .where(live_pairs_clauses.reduce(:or))
      )
    end

    def incoming_account_class
      @incoming_account_class ||= @incoming_source_class&.reflect_on_association(:account)&.klass
    end

    def live_transactions_for(account_class)
      account_class.transaction_class
        .where(account_id: live_accounts_for(account_class).select(:id))
        .select(:id)
    end

    def live_accounts_for(account_class)
      account_class
        .joins(:account_sources)
        .where(connection_id: connections_for(account_class).select(:id))
    end

    def case_insensitive_eq(column, value)
      lower_col(column).eq(lower_quoted(value))
    end

    # Bidirectional case-insensitive "starts with" using LEFT/LENGTH instead of
    # LIKE. LIKE would require escaping `%`, `_`, and `\` from the stored
    # description on the value-starts-with-column side, where the stored value
    # would otherwise be interpolated into the LIKE pattern. LEFT(...) = ...
    # avoids pattern semantics entirely.
    #
    # The reverse branch (value-starts-with-column) requires an explicit
    # non-empty-column guard. Without it, `LEFT(value, 0) = ''` would always
    # equal `LOWER('')`, so a single blank stored description with the same
    # amount/day/account would be adopted under any nonblank importing
    # description. The forward branch is unaffected: `LEFT('', N) = ''` cannot
    # equal a nonblank importing value (we early-return on blank @description).
    def prefix_match(column, value)
      column_lower = lower_col(column)
      value_lower = lower_quoted(value)

      column_starts_with_value = left_function(column_lower, value.length).eq(value_lower)
      value_starts_with_column = length_function(column_lower).gt(0)
        .and(left_function(value_lower, length_function(column_lower)).eq(column_lower))

      column_starts_with_value.or(value_starts_with_column)
    end

    # prefix_match over descriptions with their masked digit runs collapsed (#221).
    #
    # Both sides are normalized in SQL rather than normalizing the value in Ruby, so the column
    # and the value pass through the same regex engine and the same collation — there is no way
    # for Ruby's downcase/gsub to disagree with Postgres's LOWER/REGEXP_REPLACE on some input.
    # That makes the prefix lengths LENGTH() nodes instead of Ruby integers; left_function
    # already accepts a node there.
    #
    # The non-empty-column guard carries over from prefix_match for the same reason: without it
    # a blank stored description would be adopted under any nonblank importing one. Normalizing
    # cannot introduce a new blank — a nonblank input always yields a nonblank output, since a
    # collapsed run is replaced by a character rather than removed.
    def normalized_prefix_match(column, value)
      column_normalized = normalized(lower_col(column))
      value_normalized = normalized(lower_quoted(value))

      column_starts_with_value = left_function(column_normalized, length_function(value_normalized))
        .eq(value_normalized)
      value_starts_with_column = length_function(column_normalized).gt(0)
        .and(left_function(value_normalized, length_function(column_normalized)).eq(column_normalized))

      column_starts_with_value.or(value_starts_with_column)
    end

    # The pattern is a constant and the value side is a quoted string literal, never a pattern,
    # so no caller-supplied text is ever interpreted as a regular expression here.
    def normalized(node)
      Arel::Nodes::NamedFunction.new("REGEXP_REPLACE", [
        node,
        Arel::Nodes::Quoted.new(MASKED_RUN_PATTERN),
        Arel::Nodes::Quoted.new(MASKED_RUN_PLACEHOLDER),
        Arel::Nodes::Quoted.new("g")
      ])
    end

    def left_function(node, length)
      length_node = length.is_a?(Integer) ? Arel::Nodes::Quoted.new(length) : length
      Arel::Nodes::NamedFunction.new("LEFT", [ node, length_node ])
    end

    def length_function(node)
      Arel::Nodes::NamedFunction.new("LENGTH", [ node ])
    end

    def lower_col(column)
      Arel::Nodes::NamedFunction.new("LOWER", [ column ])
    end

    def lower_quoted(value)
      Arel::Nodes::NamedFunction.new("LOWER", [ Arel::Nodes::Quoted.new(value) ])
    end

    def connections_for(account_class)
      account_class.reflect_on_association(:connection).klass
        .where(user_id: @ledger_account.user_id)
    end
end
