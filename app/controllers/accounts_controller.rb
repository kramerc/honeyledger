class AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, only: %i[ show edit update destroy ]

  # GET /accounts or /accounts.json
  def index
    @accounts = current_user.accounts.includes(:currency, :opening_balance_transaction)
  end

  # GET /accounts/1 or /accounts/1.json
  def show
  end

  # GET /accounts/new
  def new
    @account = current_user.accounts.build
    @account.build_opening_balance_transaction
  end

  # GET /accounts/1/edit
  def edit
    if @account.opening_balance_transaction.nil?
      @account.build_opening_balance_transaction
    end
  end

  # POST /accounts or /accounts.json
  def create
    @account = current_user.accounts.build(account_params)
    update_opening_balance_transaction

    respond_to do |format|
      if @account.save
        format.html { redirect_to @account, notice: "Account was successfully created." }
        format.json { render :show, status: :created, location: @account }
      else
        p @account.errors
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @account.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /accounts/1 or /accounts/1.json
  def update
    @account.assign_attributes(account_params)
    update_opening_balance_transaction

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

  # DELETE /accounts/1 or /accounts/1.json
  def destroy
    @account.destroy!

    respond_to do |format|
      format.html { redirect_to accounts_path, notice: "Account was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_account
      @account = current_user.accounts.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def account_params
      params.expect(account: [ :name, :kind, :currency_id, opening_balance_transaction_attributes: [ :amount_minor, :transacted_at ] ])
    end

    def update_opening_balance_transaction
      return unless @account.opening_balance_transaction.present?

      # Handle opening balance transaction
      if @account.opening_balance_transaction.amount_minor.positive?
        opening_balance_tx = @account.opening_balance_transaction
        opening_balance_tx.user = current_user
        opening_balance_tx.src_account = Account.find_or_create_by(user: current_user, name: "Opening Balances", kind: :revenue, currency: @account.currency)
        opening_balance_tx.dest_account = @account
        opening_balance_tx.description = "Opening balance"
        opening_balance_tx.currency = @account.currency
        opening_balance_tx.opening_balance = true
        opening_balance_tx.cleared_at = opening_balance_tx.transacted_at
      else
        @account.opening_balance_transaction = nil
      end
    end
end
