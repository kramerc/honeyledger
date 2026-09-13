# Sensitive account changes (adding a passkey) require proof that the person
# at the keyboard authenticated recently: either the session itself is fresh,
# or they re-entered their password through ReauthenticationsController.
module RecentAuthentication
  extend ActiveSupport::Concern

  RECENT_AUTHENTICATION_WINDOW = 10.minutes

  included do
    helper_method :recently_authenticated?
  end

  private
    def recently_authenticated?
      Current.session.created_at > RECENT_AUTHENTICATION_WINDOW.ago || reauthenticated_recently?
    end

    def reauthenticated_recently?
      reauthenticated_at = session[:reauthenticated_at]
      reauthenticated_at.present? && Time.zone.parse(reauthenticated_at) > RECENT_AUTHENTICATION_WINDOW.ago
    end

    def require_recent_authentication
      return if recently_authenticated?

      if request.format.json?
        head :forbidden
      else
        redirect_to new_reauthentication_path
      end
    end

    def record_reauthentication
      session[:reauthenticated_at] = Time.current.iso8601
    end
end
