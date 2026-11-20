require "test_helper"

# Capybara 3.40 (the latest release) ends each Chrome session reset with the
# DevTools call Storage.clearDataForOrigin(origin: "*"). Chrome 158 rejects
# "*" as an invalid URL, so every system test errored in teardown. Clear the
# app server's own origin instead, which is the only one the tests visit.
# Drop this once Capybara stops sending the wildcard.
module ChromeStorageClearForAppOrigin
  private

  def execute_cdp(cmd, params = {})
    if cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"
      origin = Capybara.current_session.server&.base_url
      return if origin.nil?

      params = params.merge(origin: origin)
    end
    super
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageClearForAppOrigin)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444"
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  end

  # Logs in through the real form. Shares its name with the cookie-based
  # SessionTestHelper#sign_in_as used by integration tests, so a test reads the
  # same way regardless of its base class. Every user fixture carries the
  # "password123" digest.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_link "Logout"
  end
end
