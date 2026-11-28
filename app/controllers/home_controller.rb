class HomeController < ApplicationController
  allow_unauthenticated_access

  # The public landing page. It carries no user data; a signed-in user goes
  # straight to the dashboard instead.
  def index
    redirect_to dashboard_path if authenticated?
  end
end
