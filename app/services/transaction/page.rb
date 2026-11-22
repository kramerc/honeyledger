# One page of the transactions index, by keyset (cursor) pagination over its
# (transacted_at, created_at, id) order, newest first.
#
# The cursor holds the last row's sort values rather than its id, so deleting
# that row before the next page loads cannot break the request, and rows
# inserted above it cannot shift later pages the way an OFFSET would.
class Transaction::Page
  SIZE = 50

  # Rows strictly below a (transacted_at, created_at, id) position in the
  # index's order, as a Postgres row-value comparison.
  BELOW = "(transactions.transacted_at, transactions.created_at, transactions.id) < (?, ?, ?)".freeze

  ORDER = { transacted_at: :desc, created_at: :desc, id: :desc }.freeze

  Cursor = Data.define(:transacted_at, :created_at, :id) do
    # The range Postgres can compare against: bigint ids and timestamp years.
    ID_RANGE = (1..(2**63 - 1))
    YEAR_RANGE = (1..9999)

    # Reads before_at / before_created / before_id. nil (the first page) when
    # any part is missing, malformed, or out of the database's range.
    def self.from_params(params)
      values = params.values_at(:before_at, :before_created, :before_id)
      return if values.any?(&:blank?)

      transacted_at = Time.iso8601(values[0].to_s)
      created_at = Time.iso8601(values[1].to_s)
      id = Integer(values[2].to_s, 10)
      return unless ID_RANGE.cover?(id) && YEAR_RANGE.cover?(transacted_at.year) && YEAR_RANGE.cover?(created_at.year)

      new(transacted_at, created_at, id)
    rescue ArgumentError
      nil
    end

    def self.after(transaction)
      new(transaction.transacted_at, transaction.created_at, transaction.id)
    end

    def to_params
      { before_at: transacted_at.iso8601(6), before_created: created_at.iso8601(6), before_id: id }
    end
  end

  # `scope` the rows that sort strictly below `transaction`, nearest first.
  def self.below(scope, transaction)
    scope.where(BELOW, transaction.transacted_at, transaction.created_at, transaction.id).order(ORDER)
  end

  # Rows per page. A method rather than only the constant, so tests can stub it.
  def self.size
    SIZE
  end

  attr_reader :transactions, :next_cursor

  def initialize(scope, cursor: nil, size: self.class.size)
    scope = scope.reorder(ORDER)
    scope = scope.where(BELOW, cursor.transacted_at, cursor.created_at, cursor.id) if cursor
    rows = scope.limit(size + 1).to_a

    @transactions = rows.first(size)
    @next_cursor = Cursor.after(@transactions.last) if rows.size > size
  end
end
