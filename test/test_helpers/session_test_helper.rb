module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  # Each request runs in its own Current context and pops back to the test's
  # afterwards, so Current.session only ever holds what the test itself set.
  # A session started by a request (the login form) is only reachable through
  # the cookie, so resolve it from there rather than trusting Current.
  def sign_out
    Session.find_by(id: signed_session_id)&.destroy!
    Current.session = nil
    cookies.delete("session_id")
  end

  private
    def signed_session_id
      return if cookies["session_id"].blank?

      ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
        cookie_jar[:session_id] = cookies["session_id"]
      end.signed[:session_id]
    end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
