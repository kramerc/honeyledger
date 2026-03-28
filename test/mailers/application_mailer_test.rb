require "test_helper"

class ApplicationMailerTest < ActiveSupport::TestCase
  test "has correct default from address" do
    assert_equal "from@example.com", ApplicationMailer.default[:from]
  end
end
