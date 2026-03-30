require "test_helper"

class Lunchflow::ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @lunchflow_connection = lunchflow_connections(:one)
  end

  test "validates uniqueness of user_id" do
    duplicate = Lunchflow::Connection.new(
      user: @lunchflow_connection.user,
      api_key: "another_key"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "validates presence of api_key" do
    connection = Lunchflow::Connection.new(
      user: users(:one),
      api_key: nil
    )

    assert_not connection.valid?
    assert_includes connection.errors[:api_key], "can't be blank"
  end

  test "client returns a LunchflowClient" do
    client = @lunchflow_connection.client

    assert_instance_of LunchflowClient, client
  end

  test "refresh enqueues Lunchflow::RefreshJob" do
    assert_enqueued_with(job: Lunchflow::RefreshJob, args: [ @lunchflow_connection.id ]) do
      @lunchflow_connection.refresh
    end
  end
end
