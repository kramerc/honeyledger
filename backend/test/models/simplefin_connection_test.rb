require "test_helper"

class SimplefinConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @connection = simplefin_connections(:one)
  end

  test "should validate uniqueness of user_id" do
    duplicate_connection = SimplefinConnection.new(
      user: @user,
      url: "https://example.com/simplefin"
    )

    assert_not duplicate_connection.valid?
    assert_includes duplicate_connection.errors[:user_id], "has already been taken"
  end

  test "client returns a Simplefin instance" do
    client = @connection.client

    assert_instance_of Simplefin, client
  end

  test "claim_demo! sets demo URL and refreshes" do
    @connection.url = nil

    assert_enqueued_with(job: SimplefinRefreshJob, args: [ @connection.id ]) do
      @connection.claim_demo!
    end

    assert_equal SimplefinConnection::DEMO_URL, @connection.url
    assert_nil @connection.refreshed_at
  end

  test "claim! with demo flag calls claim_demo!" do
    @connection.demo = "1"
    @connection.url = nil

    assert_enqueued_with(job: SimplefinRefreshJob) do
      @connection.claim!
    end

    assert_equal SimplefinConnection::DEMO_URL, @connection.url
  end

  test "claim! with setup token claims connection" do
    @connection.setup_token = "test_token"
    @connection.demo = "0"
    claimed_url = "https://claimed.simplefin.org/simplefin"

    # Mock the Simplefin client's claim method
    simplefin = Minitest::Mock.new
    simplefin.expect :claim, claimed_url, [ "test_token" ]

    Simplefin.stub :new, simplefin do
      assert_enqueued_with(job: SimplefinRefreshJob) do
        @connection.claim!
      end
    end

    assert_equal claimed_url, @connection.url
    assert_nil @connection.refreshed_at
    simplefin.verify
  end

  test "claim! raises error without setup token" do
    @connection.setup_token = nil
    @connection.demo = "0"

    error = assert_raises(RuntimeError) do
      @connection.claim!
    end

    assert_equal "Setup token required to claim connection", error.message
  end

  test "refresh enqueues SimplefinRefreshJob" do
    assert_enqueued_with(job: SimplefinRefreshJob, args: [ @connection.id ]) do
      @connection.refresh
    end
  end
end
