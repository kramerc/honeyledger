class Simplefin::ConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :fail_if_connected, only: %i[new create]
  before_action :set_simplefin_connection, only: %i[refresh destroy]

  def new
    @simplefin_connection = current_user.build_simplefin_connection
  end

  def create
    @simplefin_connection = current_user.build_simplefin_connection(simplefin_connection_params)

    respond_to do |format|
      if @simplefin_connection.save
        begin
          @simplefin_connection.claim!
          format.html { redirect_to integrations_path, notice: "Connected to SimpleFIN successfully." }
          format.json { head :created }
        rescue => e
          @simplefin_connection.destroy
          flash.now[:alert] = "Failed to claim SimpleFIN connection: #{e.message}"
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @simplefin_connection.errors, status: :unprocessable_entity }
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @simplefin_connection.errors, status: :unprocessable_entity }
      end
    end
  end

  def refresh
    @simplefin_connection.refresh
    redirect_to integrations_path, notice: "SimpleFIN refresh enqueued."
  end

  def destroy
    @simplefin_connection.destroy!

    respond_to do |format|
      format.html { redirect_to integrations_path, notice: "Disconnected from SimpleFIN successfully.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

    def fail_if_connected
      return unless current_user.simplefin_connection

      respond_to do |format|
        format.html { redirect_to integrations_path, alert: "You already have a SimpleFIN connection." }
        format.json { render json: { error: "You already have a SimpleFIN connection." }, status: :unprocessable_entity }
      end
    end

    def set_simplefin_connection
      @simplefin_connection = Simplefin::Connection.find_by!(user: current_user)
    end

    def simplefin_connection_params
      params.expect(simplefin_connection: [ :setup_token, :demo ])
    end
end
