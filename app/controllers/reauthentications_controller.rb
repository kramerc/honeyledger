# Re-confirms the signed-in user's password so that RecentAuthentication
# treats the session as fresh again.
class ReauthenticationsController < ApplicationController
  include RecentAuthentication

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_reauthentication_path, alert: "Try again later." }

  def new
  end

  def create
    if current_user.authenticate(params[:password].to_s)
      record_reauthentication
      redirect_to settings_path, notice: "Password confirmed."
    else
      redirect_to new_reauthentication_path, alert: "That password is not right."
    end
  end
end
