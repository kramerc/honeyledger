class Transaction::AdoptOrphan
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(ledger_account:, amount_minor:, currency_id:, transacted_at:, description:)
    @ledger_account = ledger_account
    @amount_minor = amount_minor
    @currency_id = currency_id
    @transacted_at = transacted_at
    @description = description
  end

  def call
    return nil if @description.blank?

    candidates = candidate_query.limit(2).to_a
    candidates.size == 1 ? candidates.first : nil
  end

  private

    def candidate_query
      Transaction
        .where(user_id: @ledger_account.user_id)
        .where("transactions.src_account_id = :id OR transactions.dest_account_id = :id", id: @ledger_account.id)
        .where(amount_minor: @amount_minor, currency_id: @currency_id)
        .where(transacted_at: @transacted_at.beginning_of_day..@transacted_at.end_of_day)
        .where(opening_balance: false, split: false, parent_transaction_id: nil)
        .where(merged_into_id: nil, fx_amount_minor: nil)
        .where.missing(:merged_sources)
        .where(orphan_with_description_clause)
    end

    # Manual-entry orphans (sourceable_id IS NULL) require an exact case-insensitive
    # description match — preserves #117 safety so a user's manual placeholder cannot
    # be scooped up by an unrelated long aggregator description that happens to share
    # a short prefix.
    #
    # Stale-aggregator orphans (sourceable points into any aggregator's stale-account
    # transaction set) use a bidirectional case-insensitive prefix match — covers the
    # cross-aggregator truncation case (e.g. Lunch Flow's 32-char merchant truncation
    # of a longer SimpleFIN description).
    def orphan_with_description_clause
      table = Transaction.arel_table

      manual_entry = table[:sourceable_id].eq(nil)
        .and(case_insensitive_eq(table[:description], @description))

      aggregator_clauses = AggregatorLinkable.registry.map do |account_class|
        table[:sourceable_type].eq(account_class.transaction_class.name)
          .and(table[:sourceable_id].in(stale_transactions_for(account_class).arel))
      end
      stale_aggregator = aggregator_clauses.reduce(:or)
        &.and(prefix_match(table[:description], @description))

      stale_aggregator ? manual_entry.or(stale_aggregator) : manual_entry
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

    def stale_transactions_for(account_class)
      account_class.transaction_class
        .where(account_id: stale_accounts_for(account_class).select(:id))
        .select(:id)
    end

    def stale_accounts_for(account_class)
      account_class
        .where.missing(:ledger_account)
        .where(connection_id: connections_for(account_class).select(:id))
    end

    def connections_for(account_class)
      account_class.reflect_on_association(:connection).klass
        .where(user_id: @ledger_account.user_id)
    end
end
