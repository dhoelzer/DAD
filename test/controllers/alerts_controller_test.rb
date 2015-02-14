require 'test_helper'

class AlertsControllerTest < ActionController::TestCase
  setup do
    @alert = alerts(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:alerts)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create alert" do
    assert_difference('Alert.count') do
      post :create, alert: { closed: @alert.closed, criticality: @alert.criticality, description: @alert.description, event_id: @alert.event_id, generated: @alert.generated, service_id: @alert.service_id, short_description: @alert.short_description, system_id: @alert.system_id }
    end

    assert_redirected_to alert_path(assigns(:alert))
  end

  test "should show alert" do
    get :show, id: @alert
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @alert
    assert_response :success
  end

  test "should update alert" do
    patch :update, id: @alert, alert: { closed: @alert.closed, criticality: @alert.criticality, description: @alert.description, event_id: @alert.event_id, generated: @alert.generated, service_id: @alert.service_id, short_description: @alert.short_description, system_id: @alert.system_id }
    assert_redirected_to alert_path(assigns(:alert))
  end

  test "should destroy alert" do
    assert_difference('Alert.count', -1) do
      delete :destroy, id: @alert
    end

    assert_redirected_to alerts_path
  end
end
