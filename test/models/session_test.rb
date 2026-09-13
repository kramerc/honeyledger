require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "belongs to a user and defaults request metadata to empty strings" do
    session = users(:one).sessions.create!

    assert_equal users(:one), session.user
    assert_equal "", session.ip_address
    assert_equal "", session.user_agent
  end
end
