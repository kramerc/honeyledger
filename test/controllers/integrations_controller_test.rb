require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "should get show" do
    get integrations_url
    assert_response :success
  end

  test "should show when no connections exist" do
    @user.simplefin_connection&.destroy!
    @user.lunchflow_connection&.destroy!

    get integrations_url
    assert_response :success
  end

  test "requires authentication" do
    sign_out @user

    get integrations_url
    assert_redirected_to new_user_session_url
  end

  test "should show with lunchflow connection error" do
    @user.lunchflow_connection.update!(error: "Active subscription required.")

    get integrations_url
    assert_response :success
  end

  test "should show with simplefin errlist" do
    @user.simplefin_connection.update!(errlist: [ { "code" => "auth", "msg" => "Login expired" } ])

    get integrations_url
    assert_response :success
  end

  test "hides stale unlinked simplefin accounts" do
    @user.simplefin_connection.update!(refreshed_at: Time.current)
    stale_unlinked = simplefin_accounts(:unlinked_one)
    stale_unlinked.update!(last_seen_at: 1.day.ago)

    get integrations_url

    assert_response :success
    assert_no_match stale_unlinked.name, response.body
  end

  test "shows current unlinked simplefin accounts" do
    @user.simplefin_connection.update!(refreshed_at: 1.hour.ago)
    current_unlinked = simplefin_accounts(:unlinked_one)
    current_unlinked.update!(last_seen_at: Time.current)

    get integrations_url

    assert_response :success
    assert_match current_unlinked.name, response.body
  end

  test "shows stale linked simplefin accounts" do
    @user.simplefin_connection.update!(refreshed_at: Time.current)
    stale_linked = simplefin_accounts(:linked_one)
    stale_linked.update!(last_seen_at: 1.day.ago)

    get integrations_url

    assert_response :success
    assert_match stale_linked.name, response.body
  end

  test "hides stale unlinked lunchflow accounts" do
    @user.lunchflow_connection.update!(refreshed_at: Time.current)
    stale_unlinked = lunchflow_accounts(:unlinked_one)
    stale_unlinked.update!(last_seen_at: 1.day.ago)

    get integrations_url

    assert_response :success
    assert_no_match stale_unlinked.name, response.body
  end

  test "shows current unlinked lunchflow accounts" do
    @user.lunchflow_connection.update!(refreshed_at: 1.hour.ago)
    current_unlinked = lunchflow_accounts(:unlinked_one)
    current_unlinked.update!(last_seen_at: Time.current)

    get integrations_url

    assert_response :success
    assert_match current_unlinked.name, response.body
  end

  test "shows stale linked lunchflow accounts" do
    @user.lunchflow_connection.update!(refreshed_at: Time.current)
    stale_linked = lunchflow_accounts(:linked_one)
    stale_linked.update!(last_seen_at: 1.day.ago)

    get integrations_url

    assert_response :success
    assert_match stale_linked.name, response.body
  end
end
