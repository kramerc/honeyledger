class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_filter_account
  before_action :set_transaction, only: %i[ show edit update destroy ]
  before_action :set_form_collections, only: %i[ index new create edit update show ]

  # GET /transactions or /transactions.json
  def index
    @new_transaction = build_new_transaction

    @show_excluded = params[:show_excluded] == "1"
    @transactions = visible_transactions(show_excluded: @show_excluded)
      .includes(:category, :src_account, :dest_account, :currency, :fx_currency, transaction_sources: :sourceable, merged_sources: [ :src_account, :dest_account, { transaction_sources: :sourceable } ])
      .order(transacted_at: :desc, created_at: :desc)
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
          @row_visible = row_visible?(@transaction)
          @last_transaction = find_preceding_transaction(@transaction) if @row_visible
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
        scope = visible_transactions(show_excluded: show_excluded?)
        restored = unmerger.restored_transactions
          .sort_by { |t| [ t.transacted_at, t.created_at ] }.reverse
        # Only legs that belong in the list being rendered can be inserted; an
        # account-filtered index may exclude some or all of them.
        visible_ids = scope.where(id: restored.map(&:id)).pluck(:id)
        @restored_transactions = restored.select { |t| visible_ids.include?(t.id) }

        # Find the nearest transaction that's newer (appears above in the list) to insert after.
        # This element is already in the DOM, unlike older ones which may be off-screen or absent.
        newest = @restored_transactions.first
        @after_transaction = if newest
          scope.where.not(id: restored.map(&:id))
            .where("transacted_at > :at OR (transacted_at = :at AND created_at > :cat)",
                   at: newest.transacted_at, cat: newest.created_at)
            .order(transacted_at: :asc, created_at: :asc).first
        end
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
        @row_visible = row_visible?(@merged_transaction)
        @last_transaction = find_preceding_transaction(@merged_transaction) if @row_visible
        @removed_ids = [ transaction_a.id, transaction_b.id ]
        format.turbo_stream
      else
        @merge_errors = merger.errors
        format.turbo_stream { render :merge_error, status: :unprocessable_entity }
      end
    end
  end

  # POST /transactions/deduplicate
  def deduplicate
    transaction_ids = Array(params[:transaction_ids]).uniq
    if transaction_ids.size < 2
      @dedupe_errors = [ "You must select at least two transactions to combine." ]
      respond_to do |format|
        format.turbo_stream { render :dedupe_error, status: :unprocessable_entity }
      end
      return
    end

    transactions = current_user.transactions.where(id: transaction_ids).to_a
    # Any missing/foreign id leaves the set short — 404, matching find's behavior.
    raise ActiveRecord::RecordNotFound if transactions.size != transaction_ids.size

    survivor = nil
    if params[:survivor_id].present?
      survivor = transactions.find { |t| t.id.to_s == params[:survivor_id].to_s }
      if survivor.nil?
        @dedupe_errors = [ "The transaction to keep must be one of the selected transactions." ]
        respond_to do |format|
          format.turbo_stream { render :dedupe_error, status: :unprocessable_entity }
        end
        return
      end
    end

    deduplicator = Transaction::Deduplicate.new(*transactions, user: current_user, survivor: survivor)

    succeeded = false
    Transaction.collecting_sidebar_broadcasts do
      succeeded = deduplicator.call
    end

    respond_to do |format|
      if succeeded
        @survivor = deduplicator.survivor
        @removed_ids = transactions.reject { |t| t.id == @survivor.id }.map(&:id)
        format.turbo_stream
      else
        @dedupe_errors = deduplicator.errors
        format.turbo_stream { render :dedupe_error, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /transactions/bulk_destroy
  def bulk_destroy
    transactions = current_user.transactions.where(id: bulk_transaction_ids).to_a
    @removed_ids = transactions.map(&:id)

    Transaction.collecting_sidebar_broadcasts do
      ActiveRecord::Base.transaction do
        # Re-fetch per id so cascade-deleted children (dependent: :destroy) are
        # not destroyed twice, which would reverse their balances twice.
        @removed_ids.each do |id|
          current_user.transactions.find_by(id: id)&.destroy!
        end
      end
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  # POST /transactions/bulk_exclude
  def bulk_exclude
    @excluded = []
    @exclude_errors = []
    @show_excluded = show_excluded?

    Transaction.collecting_sidebar_broadcasts do
      current_user.transactions.where(id: bulk_transaction_ids).find_each do |transaction|
        excluder = Transaction::Exclude.new(transaction, user: current_user)
        if excluder.call
          @excluded << transaction.reload
        else
          @exclude_errors.concat(excluder.errors)
        end
      end
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  # POST /transactions/bulk_unexclude
  def bulk_unexclude
    @restored = []
    @exclude_errors = []

    Transaction.collecting_sidebar_broadcasts do
      current_user.transactions.where(id: bulk_transaction_ids).find_each do |transaction|
        unexcluder = Transaction::Unexclude.new(transaction, user: current_user)
        if unexcluder.call
          @restored << transaction.reload
        else
          @exclude_errors.concat(unexcluder.errors)
        end
      end
    end

    respond_to do |format|
      format.turbo_stream
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
            render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction", locals: { transaction: @transaction })
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
        format.turbo_stream { render turbo_stream: turbo_stream.replace(@transaction, partial: "transactions/transaction", locals: { transaction: @transaction }) }
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

    # The account the index is filtered to, threaded through mutating requests by
    # a hidden field so Turbo Stream insertions can be scoped to the same list.
    def set_filter_account
      account_id = params[:account_id]
      @account = current_user.accounts.find(account_id) if account_id.present?
    end

    def bulk_transaction_ids
      Array(params[:transaction_ids]).uniq
    end

    def build_new_transaction
      current_user.transactions.build(transacted_at: Time.current)
    end

    # Only allow a list of trusted parameters through.
    def transaction_params
      params.expect(transaction: [
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
        :cleared
      ])
    end

    # The rows the index is currently rendering. Turbo Stream insertions must be
    # anchored inside this same scope, or they target a DOM id that isn't on the
    # page and Turbo drops them silently.
    def visible_transactions(show_excluded:)
      scope = current_user.transactions.unmerged
      scope = scope.unexcluded unless show_excluded
      if @account
        scope = scope.where(src_account_id: @account.id).or(scope.where(dest_account_id: @account.id))
      end
      scope
    end

    def row_visible?(transaction)
      visible_transactions(show_excluded: show_excluded?).exists?(id: transaction.id)
    end

    # The nearest row that sorts below `transaction`, i.e. the one it must be
    # inserted before. The predicate mirrors the (transacted_at, created_at)
    # sort order exactly, so a row older by date but newer by creation still
    # counts as below.
    def find_preceding_transaction(transaction)
      visible_transactions(show_excluded: show_excluded?)
        .where("transacted_at < :at OR (transacted_at = :at AND created_at < :cat)",
               at: transaction.transacted_at, cat: transaction.created_at)
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
