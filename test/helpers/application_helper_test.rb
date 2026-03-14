require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # Provide a controllable request for helpers that call request.path / current_page?
  def request
    @mock_request ||= ActionDispatch::TestRequest.create
  end

  def with_path(path)
    request.env["PATH_INFO"] = path
  end

  setup do
    with_path("/")
  end

  # nav_link_to

  test "nav_link_to renders a link with the given name and url" do
    result = nav_link_to("Home", "/")
    assert_match(/Home/, result)
    assert_match(/href="\//, result)
  end

  test "nav_link_to has active class when on the exact page" do
    with_path("/categories")
    result = nav_link_to("Categories", "/categories")
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to has no active class when on a different page" do
    with_path("/currencies")
    result = nav_link_to("Categories", "/categories")
    assert_no_match(/\bactive\b/, result)
  end

  test "nav_link_to does not mark a prefix path active without :prefix option" do
    with_path("/categories/new")
    result = nav_link_to("Categories", "/categories")
    assert_no_match(/\bactive\b/, result)
  end

  # nav_link_to with :prefix

  test "nav_link_to with :prefix is active on exact match" do
    with_path("/accounts")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is active on sub-path" do
    with_path("/accounts/1/transactions")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is not active on a path sharing only a string prefix" do
    with_path("/accounts_extra")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_no_match(/\bactive\b/, result)
  end

  test "nav_link_to with :prefix is not active on an unrelated path" do
    with_path("/categories")
    result = nav_link_to("Accounts", "/accounts", active: :prefix)
    assert_no_match(/\bactive\b/, result)
  end

  # nav_link_to class merging

  test "nav_link_to preserves existing classes when adding active" do
    with_path("/accounts")
    result = nav_link_to("Accounts", "/accounts", class: "nav-item", active: :prefix)
    assert_match(/\bnav-item\b/, result)
    assert_match(/\bactive\b/, result)
  end

  test "nav_link_to passes through extra html options" do
    result = nav_link_to("Logout", "/logout", data: { turbo_method: :delete })
    assert_match(/data-turbo-method="delete"/, result)
  end
end
