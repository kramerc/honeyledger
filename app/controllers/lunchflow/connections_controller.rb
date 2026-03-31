class Lunchflow::ConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :fail_if_connected, only: %i[new create]
  before_action :set_lunchflow_connection, only: %i[refresh destroy]

  def new
    @lunchflow_connection = current_user.build_lunchflow_connection
  end

  def create
    @lunchflow_connection = current_user.build_lunchflow_connection(lunchflow_connection_params)

    respond_to do |format|
      if @lunchflow_connection.save
        @lunchflow_connection.refresh
        format.html { redirect_to integrations_path, notice: "Connected to Lunch Flow successfully." }
        format.json { head :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @lunchflow_connection.errors, status: :unprocessable_entity }
      end
    end
  end

  def refresh
    @lunchflow_connection.refresh
    redirect_to integrations_path, notice: "Lunch Flow refresh enqueued."
  end

  def destroy
    @lunchflow_connection.destroy!

    respond_to do |format|
      format.html { redirect_to integrations_path, notice: "Disconnected from Lunch Flow successfully.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

    def fail_if_connected
      return unless current_user.lunchflow_connection

      respond_to do |format|
        format.html { redirect_to integrations_path, alert: "You already have a Lunch Flow connection." }
        format.json { render json: { error: "You already have a Lunch Flow connection." }, status: :unprocessable_entity }
      end
    end

    def set_lunchflow_connection
      @lunchflow_connection = Lunchflow::Connection.find_by!(user: current_user)
    end

    def lunchflow_connection_params
      params.expect(lunchflow_connection: [ :api_key ])
    end
end
