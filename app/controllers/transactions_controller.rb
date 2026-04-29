class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transaction, only: %i[ show edit update destroy ]
  before_action :set_scoped_account, only: %i[ index new create edit update show destroy exclude unexclude merge unmerge ]
  before_action :set_form_collections, only: %i[ index new create edit update show ]

  # GET /transactions or /transactions.json
  def index
    @new_transaction = build_new_transaction

    @show_excluded = params[:show_excluded] == "1"
    scope = current_user.transactions.unmerged
    scope = scope.unexcluded unless @show_excluded
    @transactions = scope.includes(:category, :src_account, :dest_account, :currency, :fx_currency, merged_sources: [ :src_account, :dest_account ]).order(transacted_at: :desc, created_at: :desc)
    if @account
      @transactions = @transactions.where(src_account_id: @account.id).or(@transactions.where(dest_account_id: @account.id))
    end
  end

  # GET /transactions/1 or /transactions/1.json
  def show
  end

  # GET /transactions/new or /transactions/new.json
  def new
    @transaction = build_new_transaction
  end

  # POST /transactions or /transactions.json
  def create
    @transaction = current_user.transactions.build(transaction_params)

    respond_to do |format|
      if @transaction.save
        format.turbo_stream do
          @last_transaction = find_preceding_transaction(@transaction)
          @new_transaction = build_new_transaction
        end
        format.html { redirect_to @transaction, notice: "Transaction was successfully created." }
        format.json { render :show, status: :created, location: @transaction }
      else
        format.turbo_stream { render :new, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /transactions/1/edit or /transactions/1/edit.json
  def edit
  end

  # PATCH/PUT /transactions/1 or /transactions/1.json
  def update
    respond_to do |format|
      if @transaction.update(transaction_params)
        format.turbo_stream { render :show }
        format.html { redirect_to @transaction, notice: "Transaction was successfully updated." }
        format.json { render :show, status: :ok, location: @transaction }
      else
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /transactions/:id/unmerge
  def unmerge
    @transaction = current_user.transactions.find(params.expect(:id))

    unmerger = Transaction::Unmerge.new(@transaction, user: current_user)

    respond_to do |format|
      if unmerger.call
        @restored_transactions = unmerger.restored_transactions
          .sort_by { |t| [ t.transacted_at, t.created_at ] }.reverse
        # Find the nearest transaction that's newer (appears above in the list) to insert after.
        # This element is already in the DOM, unlike older ones which may be off-screen or absent.
        newest = @restored_transactions.first
        @after_transaction = current_user.transactions.unmerged.unexcluded
          .where.not(id: @restored_transactions.map(&:id))
          .where("transacted_at > :at OR (transacted_at = :at AND created_at > :cat)",
                 at: newest.transacted_at, cat: newest.created_at)
          .order(transacted_at: :asc, created_at: :asc).first
        @removed_id = @transaction.id
        format.turbo_stream
      else
        @merge_errors = unmerger.errors
        format.turbo_stream { render :merge_error, status: :unprocessable_entity }
      end
    end
  end

  # POST /transactions/merge
  def merge
    transaction_ids = Array(params.require(:transaction_ids)).uniq
    unless transaction_ids.size == 2
      @merge_errors = [ "You must select exactly two transactions to merge." ]
      respond_to do |format|
        format.turbo_stream { render :merge_error, status: :unprocessable_entity }
      end
      return
    end

    transaction_a = current_user.transactions.find(transaction_ids[0])
    transaction_b = current_user.transactions.find(transaction_ids[1])

    merger = Transaction::Merge.new(
      transaction_a, transaction_b,
      user: current_user,
      description: params[:description],
      transacted_at: params[:transacted_at],
      category_id: params[:category_id]
    )

    respond_to do |format|
      if merger.call
        @merged_transaction = merger.merged_transaction
        @last_transaction = find_preceding_transaction(@merged_transaction)
        @removed_ids = [ transaction_a.id, transaction_b.id ]
        format.turbo_stream
      else
        @merge_errors = merger.errors
        format.turbo_stream { render :merge_error, status: :unprocessable_entity }
      end
    end
  end

  # POST /transactions/:id/exclude
  def exclude
    @transaction = current_user.transactions.find(params.expect(:id))
    excluder = Transaction::Exclude.new(@transaction, user: current_user)

    respond_to do |format|
      if excluder.call
        @transaction.reload
        format.turbo_stream {
          if show_excluded?
            render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction", locals: { transaction: @transaction, account: @account })
          else
            render turbo_stream: turbo_stream.remove(@transaction)
          end
        }
        format.html { redirect_back fallback_location: transactions_url, notice: "Transaction was excluded." }
      else
        @exclude_errors = excluder.errors
        format.turbo_stream { render :exclude_error, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: transactions_url, alert: excluder.errors.first }
      end
    end
  end

  # POST /transactions/:id/unexclude
  def unexclude
    @transaction = current_user.transactions.find(params.expect(:id))
    unexcluder = Transaction::Unexclude.new(@transaction, user: current_user)

    respond_to do |format|
      if unexcluder.call
        @transaction.reload
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction", locals: { transaction: @transaction, account: @account }) }
        format.html { redirect_back fallback_location: transactions_url(show_excluded: 1), notice: "Transaction was restored." }
      else
        @exclude_errors = unexcluder.errors
        format.turbo_stream { render :exclude_error, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: transactions_url(show_excluded: 1), alert: unexcluder.errors.first }
      end
    end
  end

  # DELETE /transactions/1 or /transactions/1.json
  def destroy
    @transaction.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@transaction) }
      format.html { redirect_to transactions_url, notice: "Transaction was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

    # Use callbacks to share common setup or constraints between actions.
    def set_transaction
      @transaction = current_user.transactions.find(params.expect(:id))
    end

    def build_new_transaction
      current_user.transactions.build(transacted_at: Time.current)
    end

    def set_scoped_account
      account_id = params[:account_id]
      @account = current_user.accounts.find(account_id) if account_id.present?
    end

    # Only allow a list of trusted parameters through.
    def transaction_params
      raw = params.expect(transaction: [
        :transacted_at,
        :category_id,
        :src_account_id,
        :dest_account_id,
        :description,
        :amount_minor,
        :amount,
        :fx_amount_minor,
        :fx_currency_id,
        :notes,
        :cleared,
        :anchor_account_id,
        :counterparty_account_id
      ])
      translate_form_params(raw)
    end

    # Translates the form's anchor + counterparty + signed amount into the
    # model's underlying src/dest pair. Direction is inferred from the amount's
    # sign: negative → outflow (anchor as src), zero/positive/blank → inflow
    # (anchor as dest). The sign is stripped before the model sees the amount,
    # since amount_minor is always stored positive. The JSON API may continue to
    # post src_account_id/dest_account_id directly and bypass translation.
    def translate_form_params(raw)
      counterparty_id = raw[:counterparty_account_id].presence
      anchor_id = raw[:anchor_account_id].presence

      stripped = raw.except(:anchor_account_id, :counterparty_account_id)
      return stripped if counterparty_id.nil? || anchor_id.nil?

      amount_str = raw[:amount].to_s.strip
      decimal = begin
        BigDecimal(amount_str) if amount_str.present?
      rescue ArgumentError, TypeError
        nil
      end

      direction = if decimal.nil? || decimal.negative?
        "out" # blank, unparseable, or explicit minus → outflow (the common case)
      else
        "in"
      end

      src_id, dest_id = direction == "in" ? [ counterparty_id, anchor_id ] : [ anchor_id, counterparty_id ]
      # Preserve the user's typed formatting (e.g. "5.00") by stripping just the
      # leading sign rather than round-tripping through BigDecimal#to_s.
      abs_amount = amount_str.sub(/\A[+-]/, "")

      stripped.merge(src_account_id: src_id, dest_account_id: dest_id, amount: abs_amount)
    end

    def find_preceding_transaction(transaction)
      scope = current_user.transactions.unmerged
      scope = scope.unexcluded unless show_excluded?
      scope.where("transacted_at <= ? AND created_at < ?", transaction.transacted_at, transaction.created_at)
        .order(transacted_at: :desc, created_at: :desc).first
    end

    def set_form_collections
      @accounts = current_user.accounts.real.includes(:currency).order(:name)
      @categories = current_user.categories.order(:name)
    end

    def show_excluded?
      referer = request.referer
      referer.present? && URI.parse(referer).query&.include?("show_excluded=1")
    rescue URI::InvalidURIError
      false
    end
end
