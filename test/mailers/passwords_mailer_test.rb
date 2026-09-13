require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset addresses the user and links to the reset page" do
    user = users(:one)

    mail = PasswordsMailer.reset(user)

    assert_equal "Reset your password", mail.subject
    assert_equal [ user.email ], mail.to
    assert_match "/passwords/", mail.html_part.body.to_s
    assert_match "/passwords/", mail.text_part.body.to_s
  end
end
