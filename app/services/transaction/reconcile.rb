class Transaction::Reconcile
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

    candidates = candidate_query.limit(2).to_a
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
        .where(transacted_at: @transacted_at.beginning_of_day..@transacted_at.end_of_day)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(merged_into_id: nil, fx_amount_minor: nil)
        .where.missing(:merged_sources)
        .where(orphan_with_description_clause)
    end

    # Manual-entry orphans (no transaction_sources rows) require an exact
    # case-insensitive description match — preserves #117 safety so a user's
    # manual placeholder cannot be scooped up by an unrelated long aggregator
    # description that happens to share a short prefix.
    #
    # Aggregator-sourced orphans (some transaction_sources rows) use a
    # bidirectional case-insensitive prefix match — covers the cross-aggregator
    # truncation case (e.g. Lunch Flow's 32-char merchant truncation of a
    # longer SimpleFIN description). Candidates are excluded if they already
    # have a *live* source of the same aggregator type as the incoming source,
    # since the incoming sft would represent a separate real-world event.
    def orphan_with_description_clause
      table = Transaction.arel_table
      ts_table = TransactionSource.arel_table

      has_any_source = Arel::Nodes::Exists.new(
        ts_table.project(1).where(ts_table[:transaction_id].eq(table[:id]))
      )

      manual_entry = Arel::Nodes::Not.new(has_any_source)
        .and(case_insensitive_eq(table[:description], @description))

      live_collision = live_collision_subquery(ts_table)
      aggregator = has_any_source
        .and(Arel::Nodes::Not.new(live_collision))
        .and(prefix_match(table[:description], @description))

      manual_entry.or(aggregator)
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
