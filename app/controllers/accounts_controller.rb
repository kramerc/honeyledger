class AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, only: %i[ show edit update destroy ]
  before_action :set_simplefin_account, only: %i[ new create ], if: -> { simplefin_account_id.present? }
  before_action :set_lunchflow_account, only: %i[ new create ], if: -> { lunchflow_account_id.present? }

  # GET /accounts or /accounts.json
  def index
    @accounts = current_user.accounts.real.order(:kind, :name)

    respond_to do |format|
      format.html do
        # HTML-only work: eager-load for the balance/sources columns, group by
        # kind, and find which accounts can't be deleted (they still have a
        # non-opening-balance transaction; restrict_with_error). A lone
        # opening-balance transaction is auto-removed by Account#before_destroy,
        # so it doesn't count. The JSON format skips all of this and just renders
        # @accounts via index.json.jbuilder.
        @accounts = @accounts.includes(:currency, account_sources: :sourceable)
        @grouped_accounts = @accounts.group_by(&:kind)

        # Tally non-opening-balance transactions touching each account. The key set drives
        # delete-gating (any account that still has a transaction can't be destroyed via
        # restrict_with_error), and the per-account count seeds the default "keep this one"
        # choice when merging duplicates.
        account_ids = @accounts.map(&:id)
        @transaction_counts = Hash.new(0)
        unless account_ids.empty?
          Transaction.where(opening_balance: false)
            .where("src_account_id IN (:ids) OR dest_account_id IN (:ids)", ids: account_ids)
            .pluck(:src_account_id, :dest_account_id).each do |ids|
              ids.each { |id| @transaction_counts[id] += 1 }
            end
        end
        @accounts_with_transactions = @transaction_counts.keys.to_set

        # Expense/revenue accounts that no transaction references accumulate from imports and
        # merges. They're the ones safe to bulk-delete, so surface them to the header "Clean up"
        # affordance. (A merge-reference account still holds its zeroed, merged-away transaction,
        # so it stays in @accounts_with_transactions and is correctly excluded here.)
        @empty_cleanup_accounts = @accounts.select do |account|
          (account.expense? || account.revenue?) && @accounts_with_transactions.exclude?(account.id)
        end
      end
      format.json
    end
  end

  # GET /accounts/1 or /accounts/1.json
  def show
  end

  # GET /accounts/new
  def new
    @account = current_user.accounts.build

    source_account = @simplefin_account || @lunchflow_account
    if source_account
      @account.name = source_account.name
      @account.currency = Currency.find_by(code: source_account.currency)

      if (opening_balance = source_account.suggested_opening_balance)
        @account.opening_balance_amount = opening_balance[:amount]
        @account.opening_balance_transacted_at = opening_balance[:transacted_at]
      end
    end
  end

  # GET /accounts/1/edit
  def edit
  end

  # POST /accounts or /accounts.json
  def create
    @account = current_user.accounts.build(account_params)
    sourceable = @simplefin_account || @lunchflow_account

    saved =
      if sourceable && !@account.linkable?
        # Only asset/liability accounts can back an aggregator source. Refuse the
        # link rather than create an expense/revenue/equity account that the index
        # would treat as unlinkable and hide the source badge for (see the Sources
        # column gating in accounts/_account_row and Account#linkable?).
        @account.errors.add(:kind, "must be an asset or liability account to link an integration")
        false
      else
        begin
          Account.transaction do
            @account.save.tap do |ok|
              AccountSource::Attach.call(account: @account, sourceable: sourceable) if ok && sourceable
            end
          end
        rescue AccountSource::Attach::MismatchedAccount
          @account.errors.add(:base, "is already linked to another integration")
          false
        end
      end

    respond_to do |format|
      if saved
        format.html { redirect_to @account, notice: "Account was successfully created." }
        format.json { render :show, status: :created, location: @account }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /accounts/1 or /accounts/1.json
  def update
    @account.assign_attributes(account_params)

    respond_to do |format|
      if @account.save
        format.html { redirect_to @account, notice: "Account was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @account }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /accounts/merge
  # Folds the selected expense/revenue accounts into the chosen target, then redirects back
  # (Turbo Drive re-renders the whole index, reflecting the removed rows and new balance).
  def merge
    accounts = current_user.accounts.where(id: Array(params[:account_ids]))
    target = accounts.find { |account| account.id.to_s == params[:target_account_id].to_s }
    service = Account::Merge.new(target: target, sources: accounts, user: current_user)

    if target && service.call
      redirect_to accounts_path, notice: "Accounts merged into #{target.name}.", status: :see_other
    else
      redirect_to accounts_path, alert: service.errors.first || "Pick a target account to keep.", status: :see_other
    end
  end

  # DELETE /accounts/cleanup_empty
  # Bulk-deletes the user's empty expense/revenue accounts, then redirects back (Turbo Drive
  # re-renders the index, so the removed rows and the header affordance both update). Never
  # trusts the posted ids: every candidate is re-scoped to the user's expense/revenue accounts
  # and re-checked with empty? at delete time, so a stale list can't delete a non-empty account
  # (including a merge reference, whose merged-away transaction keeps it non-empty so unmerge
  # stays possible).
  def cleanup_empty
    account_ids = Array(params[:account_ids]).uniq
    candidates = current_user.accounts.where(id: account_ids, kind: %i[ expense revenue ], virtual: false)

    deleted_count = 0
    Account.transaction do
      candidates.each do |account|
        next unless account.empty?
        # Non-bang destroy: restrict_with_error returns false (without raising) if a transaction
        # landed since the empty? check, so a race degrades gracefully instead of 500ing.
        deleted_count += 1 if account.destroy
      end
    end

    notice =
      if deleted_count.zero?
        "No empty accounts to clean up."
      else
        "Deleted #{deleted_count} empty #{"account".pluralize(deleted_count)}."
      end
    redirect_to accounts_path, notice: notice, status: :see_other
  end

  # DELETE /accounts/1 or /accounts/1.json
  def destroy
    # Non-bang destroy: dependent: :restrict_with_error returns false (without
    # raising) when the account still has transactions, so it degrades to a flash
    # instead of a 500. The index hides Delete in that case, but this guards
    # direct requests and races.
    respond_to do |format|
      if @account.destroy
        format.html { redirect_to accounts_path, notice: "Account was successfully destroyed.", status: :see_other }
        format.json { head :no_content }
      else
        format.html { redirect_to accounts_path, alert: "This account still has transactions, so it can't be deleted.", status: :see_other }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  private

    # Use callbacks to share common setup or constraints between actions.
    def set_account
      @account = current_user.accounts.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def account_params
      params.expect(account: [ :name, :kind, :currency_id, :opening_balance_amount, :opening_balance_transacted_at ])
    end

    def set_simplefin_account
      simplefin_connection = current_user.simplefin_connection
      if simplefin_connection.nil?
        redirect_to new_simplefin_connection_path, alert: "Cannot import SimpleFIN account without a connection."
        return
      end

      @simplefin_account = current_user.simplefin_connection.accounts.find_by(id: simplefin_account_id)

      if @simplefin_account.nil?
        redirect_to integrations_path, alert: "SimpleFIN account to import was not found."
      elsif @simplefin_account.linked?
        redirect_to integrations_path, alert: "SimpleFIN account already linked to another account."
      end
    end

    def simplefin_account_id
      params.fetch(:simplefin_account_id, nil)
    end

    def set_lunchflow_account
      lunchflow_connection = current_user.lunchflow_connection
      if lunchflow_connection.nil?
        redirect_to new_lunchflow_connection_path, alert: "Cannot import Lunch Flow account without a connection."
        return
      end

      @lunchflow_account = current_user.lunchflow_connection.accounts.find_by(id: lunchflow_account_id)

      if @lunchflow_account.nil?
        redirect_to integrations_path, alert: "Lunch Flow account to import was not found."
      elsif @lunchflow_account.linked?
        redirect_to integrations_path, alert: "Lunch Flow account already linked to another account."
      end
    end

    def lunchflow_account_id
      params.fetch(:lunchflow_account_id, nil)
    end
end
