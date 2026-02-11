class TransactionsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :authenticate_user!
  before_action :set_transaction, only: %i[ show edit update destroy inline_edit ]

  # GET /transactions or /transactions.json
  def index
    @transactions = current_user.transactions.includes(:category, :src_account, :dest_account, :currency, :fx_currency).order(transacted_at: :desc)

    if params[:account_id].present?
      @transactions = @transactions.where(src_account_id: params[:account_id]).or(
        @transactions.where(dest_account_id: params[:account_id])
      )
    end

    @accounts_by_type = current_user.accounts.order(:name).group_by { |a| a.kind.capitalize }

    set_form_collections
    @new_transaction = current_user.transactions.build
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

  # GET /transactions/1/inline_edit
  def inline_edit
    set_form_collections
    render partial: "transaction_inline_form", locals: {
      transaction: @transaction,
      src_accounts: @src_accounts,
      dest_accounts: @dest_accounts,
      currencies: @currencies,
      categories: @categories
    }, layout: false
  end

  # POST /transactions or /transactions.json
  def create
    @transaction = current_user.transactions.build(transaction_params)

    respond_to do |format|
      if @transaction.save
        format.turbo_stream do
          set_form_collections
          new_transaction = current_user.transactions.build
          render turbo_stream: [
            turbo_stream.after("new_transaction_row",
              partial: "transactions/transaction_row",
              locals: { transaction: @transaction }
            ),
            turbo_stream.replace("new_transaction_row",
              partial: "transactions/new_transaction_row",
              locals: {
                transaction: new_transaction,
                src_accounts: @src_accounts,
                dest_accounts: @dest_accounts,
                categories: @categories
              }
            )
          ]
        end
        format.html { redirect_to @transaction, notice: "Transaction was successfully created." }
        format.json { render :show, status: :created, location: @transaction }
      else
        set_form_collections
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("new_transaction_row",
            partial: "transactions/new_transaction_row",
            locals: {
              transaction: @transaction,
              src_accounts: @src_accounts,
              dest_accounts: @dest_accounts,
              categories: @categories
            }
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /transactions/1 or /transactions/1.json
  def update
    respond_to do |format|
      if @transaction.update(transaction_params)
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@transaction),
            partial: "transactions/transaction_row",
            locals: { transaction: @transaction }
          )
        end
        format.html { redirect_to @transaction, notice: "Transaction was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @transaction }
      else
        set_form_collections
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            dom_id(@transaction),
            partial: "transactions/transaction_inline_form",
            locals: {
              transaction: @transaction,
              src_accounts: @src_accounts,
              dest_accounts: @dest_accounts,
              currencies: @currencies,
              categories: @categories
            }
          ), status: :unprocessable_entity
        end
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /transactions/1 or /transactions/1.json
  def destroy
    @transaction.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@transaction)) }
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
      permitted = params.expect(transaction: [ :transacted_at, :category_id, :category_name, :src_account_id, :dest_account_id, :description, :amount_minor, :amount_display, :currency_id, :fx_amount_minor, :fx_currency_id, :notes ])
      resolve_category!(permitted)
      resolve_amount_display!(permitted)
      permitted
    end

    # If category_name is provided, find or create the category and set category_id.
    def resolve_category!(attrs)
      # If the client did not send category_name at all, leave category_id unchanged.
      return unless attrs.key?(:category_name)

      name = attrs.delete(:category_name)&.strip

      # Explicitly clear the category when a blank name is submitted.
      if name.blank?
        attrs[:category_id] = nil
        return
      end

      category = current_user.categories.find_or_create_by!(name: name)
      attrs[:category_id] = category.id
    end

    # Convert a friendly decimal amount (e.g. "137.74") to minor units (e.g. 13774).
    def resolve_amount_display!(attrs)
      display = attrs.delete(:amount_display)
      return if display.blank?

      begin
        decimal_amount = BigDecimal(display)
      rescue ArgumentError, TypeError
        # Leave amount_minor unset so model validations can handle invalid input
        return
      end

      dest_account = current_user.accounts.find_by(id: attrs[:dest_account_id])
      decimal_places = dest_account&.currency&.decimal_places || 2
      scale = 10**decimal_places
      attrs[:amount_minor] = (decimal_amount * scale).round.to_i
    end

    def set_form_collections
      @src_accounts = current_user.accounts.sourceable.order(:name)
      @dest_accounts = current_user.accounts.destinable.order(:name)
      @currencies = Currency.all.order(:code)
      @categories = current_user.categories.order(:name)
    end
end
