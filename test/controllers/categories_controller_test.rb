require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
    @category = categories(:one)
  end

  test "should get index" do
    get categories_url
    assert_response :success
  end

  test "should get new" do
    get new_category_url
    assert_response :success
  end

  test "should create category" do
    assert_difference("Category.count") do
      post categories_url, params: { category: { icon: @category.icon, name: @category.name } }
    end

    assert_redirected_to category_url(Category.last)
  end

  test "should show category" do
    get category_url(@category)
    assert_response :success
  end

  test "should get edit" do
    get edit_category_url(@category)
    assert_response :success
  end

  test "should update category" do
    patch category_url(@category), params: { category: { icon: @category.icon, name: @category.name } }
    assert_redirected_to category_url(@category)
  end

  test "should render new when save fails on create" do
    assert_no_difference("Category.count") do
      Category.stub_any_instance :save, false do
        post categories_url, params: { category: { icon: "", name: "" } }
      end
    end

    assert_response :unprocessable_entity
  end

  test "should render edit when save fails on update" do
    original_name = @category.name

    Category.stub_any_instance :update, false do
      patch category_url(@category), params: { category: { icon: "", name: "Changed" } }
    end

    assert_response :unprocessable_entity
    assert_equal original_name, @category.reload.name
  end

  test "should destroy category" do
    assert_difference("Category.count", -1) do
      delete category_url(@category)
    end

    assert_redirected_to categories_url
  end
end
