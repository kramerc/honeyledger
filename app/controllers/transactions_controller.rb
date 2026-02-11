class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transaction, only: %i[ show edit update destroy ]

  # GET /transactions or /transactions.json
  def index
    @transactions = current_user.transactions.includes(:category, :src_account, :dest_account, :currency, :fx_currency).order(transacted_at: :desc)

    if params[:account_id].present?
      @transactions = @transactions.where(src_account_id: params[:account_id]).or(
        @transactions.where(dest_account_id: params[:account_id])
      )
    end

    @accounts_by_type = current_user.accounts.order(:name).group_by { |a| a.kind.capitalize }
  end

  # GET /transactions/1 or /transactions/1.json
  def show
  end

  # GET /transactions/new
  def new
    @transaction = current_user.transactions.build
  end

  # GET /transactions/1/edit
  def edit
  end

  # POST /transactions or /transactions.json
  def create
    @transaction = current_user.transactions.build(transaction_params)

    respond_to do |format|
      if @transaction.save
        format.html { redirect_to @transaction, notice: "Transaction was successfully created." }
        format.json { render :show, status: :created, location: @transaction }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /transactions/1 or /transactions/1.json
  def update
    respond_to do |format|
      if @transaction.update(transaction_params)
        format.html { redirect_to @transaction, notice: "Transaction was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @transaction }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /transactions/1 or /transactions/1.json
  def destroy
    @transaction.destroy!

    respond_to do |format|
      format.html { redirect_to transactions_path, notice: "Transaction was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_transaction
      @transaction = current_user.transactions.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def transaction_params
      params.expect(transaction: [ :transacted_at, :category_id, :src_account_id, :dest_account_id, :description, :amount_minor, :currency_id, :fx_amount_minor, :fx_currency_id, :notes ])
    end
end
