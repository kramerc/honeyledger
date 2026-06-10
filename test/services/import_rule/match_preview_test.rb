require "test_helper"

class ImportRule::MatchPreviewTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @currency = currencies(:usd)
    @bank_account = accounts(:linked_asset) # linked via fixture account_sources
    @expense = Account.create!(user: @user, name: "Old Groceries", kind: :expense, currency: @currency)
    @target = Account.create!(user: @user, name: "Groceries", kind: :expense, currency: @currency)

    @transaction = seed_transaction(description: "GROCERY STORE #123", remote_id: "mp_setup_1")
  end

  test "matches a transaction by contains and reports its counterpart" do
    preview = build(pattern: "grocery")

    match = preview.matches.find { |candidate| candidate.transaction.id == @transaction.id }
    assert_not_nil match
    assert_equal :expense, match.direction
    assert_equal @expense, match.current_account
  end

  test "would_move is true when assigning to a different account" do
    preview = build(pattern: "GROCERY", account_id: @target.id)
    match = preview.matches.first
    assert match.would_move
  end

  test "would_move is false when the transaction already sits in the target account" do
    preview = build(pattern: "GROCERY", account_id: @expense.id)
    match = preview.matches.first
    assert_not match.would_move
  end

  test "exclude rules always mark a match as moving" do
    preview = build(pattern: "GROCERY", exclude: true)
    match = preview.matches.first
    assert match.would_move
    assert preview.exclude?
  end

  test "matching is case-insensitive" do
    assert build(pattern: "grocery store").matches.any?
    assert build(pattern: "GROCERY STORE").matches.any?
  end

  test "supports every match type" do
    assert build(pattern: "STORE", match_type: "contains").matches.any?
    assert build(pattern: "GROCERY STORE #123", match_type: "exact").matches.any?
    assert build(pattern: "GROCERY", match_type: "starts_with").matches.any?
    assert build(pattern: "#123", match_type: "ends_with").matches.any?

    assert_empty build(pattern: "STORE", match_type: "starts_with").matches
    assert_empty build(pattern: "GROCERY", match_type: "exact").matches
  end

  test "treats LIKE metacharacters in the pattern literally" do
    literal = seed_transaction(description: "50% CASHBACK BONUS", remote_id: "mp_pct")

    assert_includes build(pattern: "50%").matches.map { |m| m.transaction.id }, literal.id
    assert_empty build(pattern: "50X", match_type: "starts_with").matches
  end

  test "blank pattern returns no matches" do
    assert_empty build(pattern: "").matches
    assert_empty build(pattern: "   ").matches
  end

  test "does not match another user's transactions" do
    other = users(:two)
    other_currency = currencies(:eur)
    other_expense = Account.create!(user: other, name: "Other Expense", kind: :expense, currency: other_currency)
    Transaction.create!(
      user: other, src_account: accounts(:two), dest_account: other_expense,
      amount_minor: 100, currency: other_currency, description: "GROCERY ELSEWHERE", transacted_at: 1.day.ago
    )

    descriptions = build(pattern: "GROCERY").matches.map { |m| m.transaction.description }
    assert_not_includes descriptions, "GROCERY ELSEWHERE"
  end

  test "lists already-excluded transactions, marked and not moving" do
    @transaction.update_columns(excluded_at: Time.current)

    match = build(pattern: "GROCERY").matches.find { |candidate| candidate.transaction.id == @transaction.id }
    assert_not_nil match
    assert match.excluded
    assert_not match.would_move
    assert_equal 0, build(pattern: "GROCERY").move_count
  end

  test "skips merged, split, and opening-balance transactions" do
    @transaction.update_columns(merged_into_id: @transaction.id)
    assert_empty build(pattern: "GROCERY").matches

    @transaction.update_columns(merged_into_id: nil, split: true)
    assert_empty build(pattern: "GROCERY").matches

    @transaction.update_columns(split: false, opening_balance: true)
    assert_empty build(pattern: "GROCERY").matches
  end

  test "caps results at the limit and flags truncation" do
    52.times { |index| seed_transaction(description: "BULK GROCERY #{index}", remote_id: "mp_bulk_#{index}") }

    preview = build(pattern: "BULK GROCERY")
    assert_equal ImportRule::MatchPreview::LIMIT, preview.matches.size
    assert preview.has_more?
    assert_equal "#{ImportRule::MatchPreview::LIMIT}+ matches", preview.count_summary
    # All visible rows are movable and the set is truncated, so the move count is "N+".
    assert_equal "#{ImportRule::MatchPreview::LIMIT}+", preview.move_count_summary
  end

  test "orders actionable matches ahead of already-excluded ones" do
    movable = seed_transaction(description: "ORDER GROCERY old", remote_id: "ord_mov")
    movable.update_columns(transacted_at: 10.days.ago)
    excluded = seed_transaction(description: "ORDER GROCERY recent", remote_id: "ord_excl")
    excluded.update_columns(transacted_at: 1.hour.ago, excluded_at: Time.current)

    matches = build(pattern: "ORDER GROCERY", account_id: @target.id).matches

    # The movable row sorts first despite being older; the excluded row sorts last.
    assert_equal movable.id, matches.first.transaction.id
    assert_not matches.first.excluded
    assert matches.last.excluded
    assert_equal 1, build(pattern: "ORDER GROCERY", account_id: @target.id).move_count
  end

  test "lists a match but does not count it as moving when it already sits in the target" do
    preview = build(pattern: "GROCERY", account_id: @expense.id)

    assert preview.matches.any?
    assert_equal 0, preview.move_count
    assert_not preview.matches.first.would_move
  end

  test "count_summary pluralizes" do
    assert_equal "1 match", build(pattern: "GROCERY STORE #123", match_type: "exact").count_summary
  end

  private

    def build(pattern:, match_type: "contains", account_id: nil, exclude: false)
      ImportRule::MatchPreview.new(
        user: @user, pattern: pattern, match_type: match_type, account_id: account_id, exclude: exclude
      )
    end

    def seed_transaction(description:, remote_id:)
      source = Simplefin::Transaction.create!(
        account: simplefin_accounts(:linked_one),
        remote_id: remote_id,
        amount: "-50.00",
        description: description,
        transacted_at: 1.day.ago,
        posted: 1.day.ago
      )
      create_sourced_transaction(
        user: @user,
        src_account: @bank_account,
        dest_account: @expense,
        amount_minor: 5000,
        currency: @currency,
        description: description,
        transacted_at: 1.day.ago,
        sourceable: source
      )
    end
end
