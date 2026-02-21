class SimplefinConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :fail_if_connected, only: %i[new create]
  before_action :set_simplefin_connection, only: %i[show destroy]

  def new
    @simplefin_connection = current_user.build_simplefin_connection
  end

  def create
    @simplefin_connection = current_user.build_simplefin_connection(simplefin_connection_params)

    respond_to do |format|
      if @simplefin_connection.save
        begin
          @simplefin_connection.claim!
          format.html { redirect_to simplefin_connection_url, notice: "Connected to Simplefin successfully." }
          format.json { render :show, status: :created, location: @simplefin_connection }
        rescue => e
          @simplefin_connection.destroy
          flash.now[:alert] = "Failed to claim Simplefin connection: #{e.message}"
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @simplefin_connection.errors, status: :unprocessable_entity }
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @simplefin_connection.errors, status: :unprocessable_entity }
      end
    end
  end

  def show
  end

  def destroy
    @simplefin_connection.destroy!

    respond_to do |format|
      format.html { redirect_to accounts_path, notice: "Disconnected from Simplefin successfully.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def fail_if_connected
    return unless current_user.simplefin_connection

    respond_to do |format|
      format.html { redirect_to simplefin_connection_url, alert: "You already have a Simplefin connection." }
      format.json { render json: { error: "You already have a Simplefin connection." }, status: :unprocessable_entity }
    end
  end

  def set_simplefin_connection
    @simplefin_connection = current_user.simplefin_connection
  end

  def simplefin_connection_params
    params.require(:simplefin_connection).permit(:setup_token, :demo)
  end
end
