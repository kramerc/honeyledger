require "test_helper"

class Simplefin::ConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @connection = simplefin_connections(:one)
  end

  test "should validate uniqueness of user_id" do
    duplicate_connection = Simplefin::Connection.new(
      user: @user,
      url: "https://example.com/simplefin"
    )

    assert_not duplicate_connection.valid?
    assert_includes duplicate_connection.errors[:user_id], "has already been taken"
  end

  test "should require setup_token on create when not in demo mode" do
    user = User.create!(
      email: "setup-token-required@example.com",
      password: "password",
      password_confirmation: "password"
    )
    connection = Simplefin::Connection.new(user: user)
    connection.demo = "0"

    assert_not connection.valid?
    assert_includes connection.errors[:setup_token], "can't be blank"
  end

  test "should not require setup_token on create when in demo mode" do
    user = User.create!(
      email: "setup-token-not-required@example.com",
      password: "password",
      password_confirmation: "password"
    )
    connection = Simplefin::Connection.new(user: user)
    connection.demo = "1"
    connection.setup_token = nil

    connection.valid?
    assert_not connection.errors[:setup_token].any?
  end

  test "should not require setup_token on update" do
    @connection.setup_token = nil
    @connection.demo = "0"

    assert @connection.valid?
  end

  test "client returns a SimplefinClient instance" do
    client = @connection.client

    assert_instance_of SimplefinClient, client
  end

  test "claim_demo! sets demo URL and refreshes" do
    @connection.url = nil

    assert_enqueued_with(job: Simplefin::RefreshJob, args: [ @connection.id ]) do
      @connection.claim_demo!
    end

    assert_equal Simplefin::Connection::DEMO_URL, @connection.url
    assert_nil @connection.refreshed_at
  end

  test "claim! with demo flag calls claim_demo!" do
    @connection.demo = "1"
    @connection.url = nil

    assert_enqueued_with(job: Simplefin::RefreshJob) do
      @connection.claim!
    end

    assert_equal Simplefin::Connection::DEMO_URL, @connection.url
  end

  test "claim! with setup token claims connection" do
    @connection.setup_token = "test_token"
    @connection.demo = "0"
    claimed_url = "https://claimed.simplefin.org/simplefin"

    # Mock the SimpleFIN client's claim method
    simplefin = Minitest::Mock.new
    simplefin.expect :claim, claimed_url, [ "test_token" ]

    SimplefinClient.stub :new, simplefin do
      assert_enqueued_with(job: Simplefin::RefreshJob) do
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

  test "refresh enqueues Simplefin::RefreshJob" do
    assert_enqueued_with(job: Simplefin::RefreshJob, args: [ @connection.id ]) do
      @connection.refresh
    end
  end
end
