class Transaction::Merge
  attr_reader :merged_transaction, :errors

  def initialize(transaction_a, transaction_b, user:, description: nil, transacted_at: nil, category_id: nil)
    @transaction_a = transaction_a
    @transaction_b = transaction_b
    @user = user
    @description = description
    @transacted_at = transacted_at
    @category_id = category_id
    @errors = []
  end

  def call
    validate!
    return false if @errors.any?

    ActiveRecord::Base.transaction do
      src_account, dest_account = determine_accounts

      @merged_transaction = ::Transaction.create!(
        user: @user,
        src_account: src_account,
        dest_account: dest_account,
        amount_minor: @transaction_a.amount_minor,
        currency: dest_account.currency,
        description: @description || @transaction_a.description,
        transacted_at: @transacted_at || [ @transaction_a.transacted_at, @transaction_b.transacted_at ].compact.min,
        cleared_at: [ @transaction_a.cleared_at, @transaction_b.cleared_at ].compact.min,
        category_id: @category_id
      )

      # Zero out originals to reverse their balance effects, then mark as merged.
      # Setting amount_minor to 0 triggers transfer_account_balances which reverses the old posting.
      [ @transaction_a, @transaction_b ].each do |t|
        t.update!(amount_minor: 0, fx_amount_minor: nil, fx_currency_id: nil, merged_into: @merged_transaction)
      end
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    @errors << e.message
    false
  end

  private

    def validate!
      unless @transaction_a.user_id == @user.id && @transaction_b.user_id == @user.id
        @errors << "Both transactions must belong to you"
      end

      unless @transaction_a.amount_minor == @transaction_b.amount_minor
        @errors << "Amounts must match"
      end

      unless @transaction_a.currency_id == @transaction_b.currency_id
        @errors << "Currencies must match"
      end

      if @transaction_a.has_fx? || @transaction_b.has_fx?
        @errors << "Foreign exchange transactions cannot be merged"
      end

      if @transaction_a.opening_balance? || @transaction_b.opening_balance?
        @errors << "Opening balance transactions cannot be merged"
      end

      if @transaction_a.split? || @transaction_b.split? ||
         @transaction_a.parent_transaction_id? || @transaction_b.parent_transaction_id?
        @errors << "Split transactions cannot be merged"
      end

      if @transaction_a.merged_into_id? || @transaction_b.merged_into_id?
        @errors << "Already merged transactions cannot be merged again"
      end

      if @transaction_a.merged_sources.any? || @transaction_b.merged_sources.any?
        @errors << "Transactions that are the result of a merge cannot be merged again"
      end

      [ @transaction_a, @transaction_b ].each do |t|
        if t.src_account.balance_sheet? && t.dest_account.balance_sheet?
          @errors << "Transactions that are already transfers cannot be merged"
          break
        end
      end

      return if @errors.any?

      src_side, dest_side = determine_sides
      if src_side.nil? || dest_side.nil?
        @errors << "One transaction must have a bank account as the source and the other must have a bank account as the destination"
      elsif src_side.src_account_id == dest_side.dest_account_id
        @errors << "Source and destination accounts cannot be the same"
      end
    end

    # Returns [src_side_transaction, dest_side_transaction] or [nil, nil]
    # src_side: the transaction whose src_account is a balance-sheet account (the "from" bank)
    # dest_side: the transaction whose dest_account is a balance-sheet account (the "to" bank)
    def determine_sides
      a_src_bs = @transaction_a.src_account.balance_sheet?
      b_src_bs = @transaction_b.src_account.balance_sheet?
      a_dest_bs = @transaction_a.dest_account.balance_sheet?
      b_dest_bs = @transaction_b.dest_account.balance_sheet?

      if a_src_bs && b_dest_bs
        [ @transaction_a, @transaction_b ]
      elsif b_src_bs && a_dest_bs
        [ @transaction_b, @transaction_a ]
      else
        [ nil, nil ]
      end
    end

    def determine_accounts
      src_side, dest_side = determine_sides
      [ src_side.src_account, dest_side.dest_account ]
    end
end
