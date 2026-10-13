require 'test_helper'

# The app's only access control is ApplicationController#gatekeeper + a per-controller
# authorized? filter. These are the invariants that filter has to keep.
class AuthorizationTest < ActionController::TestCase
  tests EventsController

  setup do
    # ApplicationController#ssl forces http -> https outside development.
    @request.env['HTTPS'] = 'on'

    @viewer_right = Right.create!(name: "Viewer", description: "can view events")
    @viewer_role  = Role.create!(name: "Viewers", description: "viewers")
    @viewer_role.rights << @viewer_right
    @viewer = User.create!(username: "viewer#{Time.now.to_i}", attempts: 0)
    @viewer.store_password("secretsauce")
    @viewer.roles << @viewer_role
    @viewer.save
  end

  def login(user)
    session = Session.create!(user: user, expiry: Time.now + 1.hour,
                              session_hash: SecureRandom.hex(16))
    cookies[:sessionID] = session.session_hash
  end

  test "anonymous users are sent to the logon page" do
    get :index
    assert_response :redirect
    assert_redirected_to logon_users_path
  end

  test "a user with the Viewer right can read events" do
    login(@viewer)
    get :index
    assert_response :success
  end

  test "passwords are never compared in the clear" do
    assert @viewer.check_password("secretsauce")
    refute @viewer.check_password("wrong")
    refute_equal "secretsauce", @viewer.password
  end
end
