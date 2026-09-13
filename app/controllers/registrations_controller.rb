class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_signed_in_users, only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome! You have signed up successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def user_params
      params.expect(user: %i[ email password password_confirmation ])
    end

    def redirect_signed_in_users
      redirect_to root_path if authenticated?
    end
end
