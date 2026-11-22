require "test_helper"

class Transaction::PageTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @time = Time.zone.parse("2026-01-15 12:00")
    # Only this test's rows, whatever the fixtures hold.
    @scope = @user.transactions.where(description: "Page row")
  end

  test "returns every row and no cursor when they fit on one page" do
    rows = Array.new(3) { |index| create_transaction(transacted_at: @time - index.days) }

    page = Transaction::Page.new(@scope, size: 3)

    assert_equal rows.map(&:id), page.transactions.map(&:id)
    assert_nil page.next_cursor
  end

  test "walks every row exactly once across pages, newest first, through ties on date and creation time" do
    # Several rows share a transacted_at, and two share created_at as well, so
    # only the id separates them at a page boundary.
    created_at = @time - 1.hour
    rows = [
      create_transaction(transacted_at: @time),
      create_transaction(transacted_at: @time - 1.day, created_at: created_at),
      create_transaction(transacted_at: @time - 1.day, created_at: created_at),
      create_transaction(transacted_at: @time - 1.day, created_at: created_at - 1.minute),
      create_transaction(transacted_at: @time - 2.days),
      create_transaction(transacted_at: @time - 3.days)
    ]
    expected = @scope.order(transacted_at: :desc, created_at: :desc, id: :desc).pluck(:id)
    assert_equal rows.map(&:id).sort, expected.sort

    seen = []
    cursor = nil
    pages = 0
    loop do
      page = Transaction::Page.new(@scope, cursor: cursor, size: 2)
      seen.concat(page.transactions.map(&:id))
      pages += 1
      cursor = page.next_cursor
      break unless cursor
    end

    assert_equal expected, seen
    assert_equal 3, pages
  end

  test "a cursor survives deleting the row it was taken from" do
    _newest, middle, oldest = Array.new(3) { |index| create_transaction(transacted_at: @time - index.days) }
    cursor = Transaction::Page.new(@scope, size: 2).next_cursor
    assert_equal middle.id, cursor.id

    middle.destroy!

    assert_equal [ oldest.id ], Transaction::Page.new(@scope, cursor: cursor, size: 2).transactions.map(&:id)
  end

  test "below returns the rows under a transaction, nearest first" do
    newest, middle, oldest = Array.new(3) { |index| create_transaction(transacted_at: @time - index.days) }

    assert_equal [ middle.id, oldest.id ], Transaction::Page.below(@scope, newest).map(&:id)
    assert_empty Transaction::Page.below(@scope, oldest)
  end

  test "cursor round-trips through params at microsecond precision" do
    transaction = create_transaction(transacted_at: @time)
    cursor = Transaction::Page::Cursor.after(transaction.reload)

    params = ActionController::Parameters.new(cursor.to_params.transform_values(&:to_s))

    assert_equal cursor, Transaction::Page::Cursor.from_params(params)
  end

  test "cursor from params is nil when a part is missing or malformed" do
    valid = { before_at: @time.iso8601(6), before_created: @time.iso8601(6), before_id: "1" }

    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new({}))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.except(:before_id)))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.merge(before_at: "yesterday")))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.merge(before_id: "one")))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.merge(before_id: "99999999999999999999")))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.merge(before_id: "0")))
    assert_nil Transaction::Page::Cursor.from_params(ActionController::Parameters.new(valid.merge(before_created: "+20000-01-01T00:00:00Z")))
  end

  private

    def create_transaction(transacted_at:, created_at: nil)
      transaction = Transaction.create!(
        user: @user, src_account: accounts(:asset_account), dest_account: accounts(:expense_account),
        amount_minor: 100, currency: @currency, description: "Page row", transacted_at: transacted_at
      )
      transaction.update_columns(created_at: created_at) if created_at
      transaction
    end
end
