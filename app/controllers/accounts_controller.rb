class AccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, only: %i[ show edit update destroy ]
  before_action :set_simplefin_account, only: %i[ new create ], if: -> { simplefin_account_id.present? }

  # GET /accounts or /accounts.json
  def index
    @accounts = current_user.accounts.real.includes(:currency)
  end

  # GET /accounts/1 or /accounts/1.json
  def show
  end

  # GET /accounts/new
  def new
    @account = current_user.accounts.build

    if @simplefin_account
      @account.name = @simplefin_account.name
      @account.currency = Currency.find_by(code: @simplefin_account.currency)

      if (opening_balance = @simplefin_account.suggested_opening_balance)
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
    @account.simplefin_account = @simplefin_account

    respond_to do |format|
      if @account.save
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
        redirect_to simplefin_connection_path, alert: "SimpleFIN account to import was not found."
      elsif @simplefin_account.linked?
        redirect_to simplefin_connection_path, alert: "SimpleFIN account already linked to another account."
      end
    end

    def simplefin_account_id
      params.fetch(:simplefin_account_id, nil)
    end
end
