class TransactionsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :authenticate_user!
  before_action :set_transaction, only: %i[ update destroy inline_edit ]

  # GET /transactions or /transactions.json
  def index
    @transactions = current_user.transactions.includes(:category, :src_account, :dest_account, :currency, :fx_currency).order(transacted_at: :desc)

    # Filter by src/dest account if account_id param is provided
    account = current_user.accounts.find_by(id: params[:account_id]) if params[:account_id].present?
    if account
      @transactions = @transactions.where(src_account_id: account).or(@transactions.where(dest_account_id: account))
    end

    @accounts_by_type = current_user.accounts.order(:name).group_by { |a| a.kind.capitalize }

    set_form_collections
    @new_transaction = current_user.transactions.build
  end

  # GET /transactions/1 or /transactions/1.json
  def show
  end

  # GET /transactions/1/inline_edit
  def inline_edit
    set_form_collections
    render partial: "form_row", locals: {
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
              partial: "transactions/row",
              locals: { transaction: @transaction }
            ),
            turbo_stream.replace("new_transaction_row",
              partial: "transactions/form_row",
              locals: {
                transaction: new_transaction,
                src_accounts: @src_accounts,
                dest_accounts: @dest_accounts,
                categories: @categories
              }
            )
          ]
        end
        format.json { render :show, status: :created, location: @transaction }
      else
        set_form_collections
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("new_transaction_row",
            partial: "transactions/form_row",
            locals: {
              transaction: @transaction,
              src_accounts: @src_accounts,
              dest_accounts: @dest_accounts,
              categories: @categories
            }
          ), status: :unprocessable_entity
        end
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
            partial: "transactions/row",
            locals: { transaction: @transaction }
          )
        end
        format.json { render :show, status: :ok, location: @transaction }
      else
        set_form_collections
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            dom_id(@transaction),
            partial: "transactions/form_row",
            locals: {
              transaction: @transaction,
              src_accounts: @src_accounts,
              dest_accounts: @dest_accounts,
              currencies: @currencies,
              categories: @categories
            }
          ), status: :unprocessable_entity
        end
        format.json { render json: @transaction.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /transactions/1 or /transactions/1.json
  def destroy
    @transaction.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@transaction)) }
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
      permitted = params.expect(transaction: [
        :transacted_at,
        :category_id,
        :category_name,
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
      resolve_category!(permitted)
      permitted
    end

    # If category_name is provided, find or create the category and set category_id.
    # If category_id is provided, use it directly (existing category selected).
    def resolve_category!(attrs)
      # If neither category_id nor category_name were sent, leave category unchanged
      return unless attrs.key?(:category_id) || attrs.key?(:category_name)

      # If category_name has a value, it's a new category - find or create it
      if attrs[:category_name].present?
        name = attrs.delete(:category_name).strip
        category = current_user.categories.find_or_create_by!(name: name)
        attrs[:category_id] = category.id
      else
        # Remove the category_name key (it was just for transport)
        attrs.delete(:category_name)
        # If category_id is blank string, convert to nil for proper clearing
        attrs[:category_id] = nil if attrs[:category_id].blank?
      end
    end

    def set_form_collections
      @src_accounts = current_user.accounts.sourceable.order(:name)
      @dest_accounts = current_user.accounts.destinable.order(:name)
      @currencies = Currency.all.order(:code)
      @categories = current_user.categories.order(:name)
    end
end
