require "test_helper"

class SimplefinConnectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "should get new" do
    # Delete existing connection so we can access the new form
    simplefin_connections(:one).destroy!

    get new_simplefin_connection_url
    assert_response :success
  end

  test "should not allow new when already connected" do
    get new_simplefin_connection_url
    assert_redirected_to simplefin_connection_url
    assert_equal "You already have a Simplefin connection.", flash[:alert]
  end

  test "should create connection" do
    # Delete existing connection so we can test creating a new one
    simplefin_connections(:one).destroy!

    assert_difference("SimplefinConnection.count") do
      post simplefin_connection_url, params: { simplefin_connection: { demo: "1" } }
    end

    assert_redirected_to simplefin_connection_url
  end

  test "should not create duplicate connection" do
    assert_no_difference("SimplefinConnection.count") do
      post simplefin_connection_url, params: { simplefin_connection: { demo: "1" } }
    end
    assert_redirected_to simplefin_connection_url
    assert_equal "You already have a Simplefin connection.", flash[:alert]
  end

  test "should show connection" do
    get simplefin_connection_url
    assert_response :success
  end

  test "should destroy connection" do
    assert_difference("SimplefinConnection.count", -1) do
      delete simplefin_connection_url
    end

    assert_redirected_to accounts_url
  end
end
