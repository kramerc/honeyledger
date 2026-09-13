class SettingsController < ApplicationController
  include RecentAuthentication

  def show
    @passkeys = current_user.passkeys.by_recency
  end
end
