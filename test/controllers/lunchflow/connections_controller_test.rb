require "test_helper"

class Lunchflow::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @lunchflow_connection = lunchflow_connections(:one)
    @user = users(:one)
    sign_in @user
  end

  test "should get new" do
    @lunchflow_connection.destroy!

    get new_lunchflow_connection_url
    assert_response :success
  end

  test "should not allow new when already connected" do
    get new_lunchflow_connection_url
    assert_redirected_to integrations_url
    assert_equal "You already have a Lunch Flow connection.", flash[:alert]
  end

  test "should create connection" do
    @lunchflow_connection.destroy!

    assert_difference("Lunchflow::Connection.count") do
      post lunchflow_connection_url, params: { lunchflow_connection: { api_key: "test_key" } }
    end

    assert_redirected_to integrations_url
    assert_equal "Connected to Lunch Flow successfully.", flash[:notice]
  end

  test "should not leak api_key in json response on create" do
    @lunchflow_connection.destroy!

    post lunchflow_connection_url, params: { lunchflow_connection: { api_key: "secret_key" } }, as: :json

    assert_response :created
    assert_empty response.body
  end

  test "should not create duplicate connection" do
    assert_no_difference("Lunchflow::Connection.count") do
      post lunchflow_connection_url, params: { lunchflow_connection: { api_key: "test_key" } }
    end
    assert_redirected_to integrations_url
    assert_equal "You already have a Lunch Flow connection.", flash[:alert]
  end

  test "should not create connection without api_key" do
    @lunchflow_connection.destroy!

    assert_no_difference("Lunchflow::Connection.count") do
      post lunchflow_connection_url, params: { lunchflow_connection: { api_key: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "should refresh connection" do
    assert_enqueued_with(job: Lunchflow::RefreshJob, args: [ @user.lunchflow_connection.id ]) do
      post refresh_lunchflow_connection_url
    end

    assert_redirected_to integrations_url
    assert_equal "Lunch Flow refresh enqueued.", flash[:notice]
  end

  test "should destroy connection" do
    assert_difference("Lunchflow::Connection.count", -1) do
      delete lunchflow_connection_url
    end

    assert_redirected_to integrations_url
  end
end
