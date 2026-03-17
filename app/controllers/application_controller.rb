class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :load_sidebar_accounts

  private

  def load_sidebar_accounts
    return unless user_signed_in?

    @accounts_by_kind = current_user.accounts.real.includes(:currency).order(:kind, :name).group_by(&:kind)
  end
end
