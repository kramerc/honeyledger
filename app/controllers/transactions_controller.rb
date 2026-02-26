class TransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transaction, only: %i[ show edit update destroy ]
  before_action :set_form_collections, only: %i[ index new create edit update show ]

  # GET /transactions or /transactions.json
  def index
    @transactions = current_user.transactions.includes(:category, :src_account, :dest_account, :currency, :fx_currency).order(transacted_at: :desc, created_at: :desc)
    @new_transaction = build_new_transaction
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
          # Find the most recent transaction before this one (by transacted_at, then created_at) to determine where to insert in the list
          @last_transaction = current_user.transactions.where("transacted_at <= ? AND created_at < ?", @transaction.transacted_at, @transaction.created_at).order(transacted_at: :desc, created_at: :desc).first
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

    def set_form_collections
      @src_accounts = current_user.accounts.sourceable.includes(:currency).order(:name)
      @dest_accounts = current_user.accounts.destinable.includes(:currency).order(:name)
      @categories = current_user.categories.order(:name)
    end
end
