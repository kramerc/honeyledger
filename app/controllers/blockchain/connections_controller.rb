class Blockchain::ConnectionsController < ApplicationController
  before_action :set_blockchain_connection, only: %i[edit update refresh destroy]

  def new
    @blockchain_connection = current_user.blockchain_connections.build(chain: "bitcoin")
  end

  def create
    @blockchain_connection = current_user.blockchain_connections.build(create_params)

    respond_to do |format|
      if @blockchain_connection.save
        @blockchain_connection.refresh
        format.html { redirect_to integrations_path, notice: "Wallet added. Its history is being fetched." }
        format.json { head :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @blockchain_connection.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  # Only the label is editable: changing the identifier would be a different wallet.
  def update
    if @blockchain_connection.update(update_params)
      redirect_to integrations_path, notice: "Wallet updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def refresh
    @blockchain_connection.refresh
    redirect_to integrations_path, notice: "Wallet refresh enqueued."
  end

  def destroy
    @blockchain_connection.destroy!

    respond_to do |format|
      format.html { redirect_to integrations_path, notice: "Wallet removed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

    def set_blockchain_connection
      @blockchain_connection = current_user.blockchain_connections.find(params.expect(:id))
    end

    def create_params
      params.expect(blockchain_connection: [ :chain, :name, :identifier ])
    end

    def update_params
      params.expect(blockchain_connection: [ :name ])
    end
end
