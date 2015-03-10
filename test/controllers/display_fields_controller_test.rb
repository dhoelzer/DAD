require 'test_helper'

class DisplayFieldsControllerTest < ActionController::TestCase
  setup do
    @display_field = display_fields(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:display_fields)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create display_field" do
    assert_difference('DisplayField.count') do
      post :create, display_field: { display_id: @display_field.display_id, field_position: @display_field.field_position, order: @display_field.order, title: @display_field.title }
    end

    assert_redirected_to display_field_path(assigns(:display_field))
  end

  test "should show display_field" do
    get :show, id: @display_field
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @display_field
    assert_response :success
  end

  test "should update display_field" do
    patch :update, id: @display_field, display_field: { display_id: @display_field.display_id, field_position: @display_field.field_position, order: @display_field.order, title: @display_field.title }
    assert_redirected_to display_field_path(assigns(:display_field))
  end

  test "should destroy display_field" do
    assert_difference('DisplayField.count', -1) do
      delete :destroy, id: @display_field
    end

    assert_redirected_to display_fields_path
  end
end
