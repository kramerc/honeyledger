class CurrenciesController < ApplicationController
  before_action :set_currency, only: %i[ show edit update destroy ]

  # GET /currencies or /currencies.json
  def index
    @currencies = Currency.all
  end

  # GET /currencies/1 or /currencies/1.json
  def show
  end

  # GET /currencies/new
  def new
    @currency = Currency.new
  end

  # GET /currencies/1/edit
  def edit
  end

  # POST /currencies or /currencies.json
  def create
    @currency = Currency.new(currency_params)

    respond_to do |format|
      if @currency.save
        format.html { redirect_to @currency, notice: "Currency was successfully created." }
        format.json { render :show, status: :created, location: @currency }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @currency.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /currencies/1 or /currencies/1.json
  def update
    respond_to do |format|
      if @currency.update(currency_params)
        format.html { redirect_to @currency, notice: "Currency was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @currency }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @currency.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /currencies/1 or /currencies/1.json
  def destroy
    @currency.destroy!

    respond_to do |format|
      format.html { redirect_to currencies_path, notice: "Currency was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_currency
      @currency = Currency.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def currency_params
      params.expect(currency: [ :name, :kind, :symbol, :code, :decimal_places, :active ])
    end
end
