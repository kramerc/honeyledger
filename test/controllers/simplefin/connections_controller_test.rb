require "test_helper"

class Simplefin::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @simplefin_connection = simplefin_connections(:one)
    @user = users(:one)
    sign_in @user
  end

  test "should get new" do
    @simplefin_connection.destroy!

    get new_simplefin_connection_url
    assert_response :success
  end

  test "should not allow new when already connected" do
    get new_simplefin_connection_url
    assert_redirected_to integrations_url
    assert_equal "You already have a SimpleFIN connection.", flash[:alert]
  end

  test "should create connection" do
    @simplefin_connection.destroy!

    assert_difference("Simplefin::Connection.count") do
      post simplefin_connection_url, params: { simplefin_connection: { demo: "1" } }
    end

    assert_redirected_to integrations_url
    assert_equal "Connected to SimpleFIN successfully.", flash[:notice]
  end

  test "should handle claim failure on create" do
    @simplefin_connection.destroy!

    Simplefin::Connection.stub_any_instance :claim!, -> { raise RuntimeError, "Claim failed" } do
      assert_no_difference("Simplefin::Connection.count") do
        post simplefin_connection_url, params: { simplefin_connection: { demo: "1" } }
      end
      assert_response :unprocessable_entity
      assert_equal "Failed to claim SimpleFIN connection: Claim failed", flash[:alert]
    end
  end

  test "should not create duplicate connection" do
    assert_no_difference("Simplefin::Connection.count") do
      post simplefin_connection_url, params: { simplefin_connection: { demo: "1" } }
    end
    assert_redirected_to integrations_url
    assert_equal "You already have a SimpleFIN connection.", flash[:alert]
  end

  test "should not create connection with invalid params" do
    @simplefin_connection.destroy!

    assert_no_difference("Simplefin::Connection.count") do
      post simplefin_connection_url, params: { simplefin_connection: { setup_token: "", demo: "0" } }
    end

    assert_response :unprocessable_entity
  end

  test "should refresh connection" do
    assert_enqueued_with(job: Simplefin::RefreshJob, args: [ @user.simplefin_connection.id ]) do
      post refresh_simplefin_connection_url
    end

    assert_redirected_to integrations_url
    assert_equal "SimpleFIN refresh enqueued.", flash[:notice]
  end

  test "should return 404 when refreshing without connection" do
    @simplefin_connection.destroy!

    post refresh_simplefin_connection_url
    assert_response :not_found
  end

  test "should return 404 when destroying without connection" do
    @simplefin_connection.destroy!

    delete simplefin_connection_url
    assert_response :not_found
  end

  test "should destroy connection" do
    assert_difference("Simplefin::Connection.count", -1) do
      delete simplefin_connection_url
    end

    assert_redirected_to integrations_url
  end
end
