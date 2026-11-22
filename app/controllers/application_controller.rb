class ApplicationController < ActionController::Base
  include Authentication
  include WebauthnRelyingParty
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # Rails' :modern set, with Firefox raised to 125 for the Popover API the row action menus use
  # (the other browsers' :modern minimums already have it).
  allow_browser versions: { safari: 17.2, chrome: 120, firefox: 125, opera: 106, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :load_sidebar_accounts

  private

  def load_sidebar_accounts
    return unless authenticated? && request.format.html?

    @accounts_by_kind = current_user.accounts.in_sidebar.includes(:currency).order(:kind, :name).group_by(&:kind)
  end
end
