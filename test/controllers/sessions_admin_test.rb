require 'test_helper'

# The Sessions screens are routed (index/show/destroy) but had no tests, and both
# HTML views raised because they linked to routes that were removed when sessions
# became read-only.
class SessionsAdminTest < ActionController::TestCase
  tests SessionsController

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: 'Admin', description: 'admin')
    role = Role.create!(name: "Admins#{SecureRandom.hex(6)}", description: 'admins')
    role.rights << right
    @admin = User.create!(username: "admin#{SecureRandom.hex(6)}", attempts: 0)
    @admin.store_password('secretsauce')
    @admin.roles << role
    @mine = Session.create!(user: @admin, expiry: Time.now + 1.hour,
                            session_hash: SecureRandom.hex(16))
    cookies[:sessionID] = @mine.session_hash
    @other = Session.create!(user: @admin, expiry: Time.now + 1.hour,
                             session_hash: 'deadbeef' * 8)
  end

  test 'index renders' do
    get :index
    assert_response :success
  end

  test 'show renders' do
    get :show, id: @other.id
    assert_response :success
  end

  # session_hash is the sole bearer credential gatekeeper accepts. The views used
  # to render session.hash -- Object#hash, a random integer -- and the JSON forms
  # extracted :hash the same way.
  test 'index does not expose a usable session token' do
    get :index
    refute_includes response.body, @other.session_hash
  end

  test 'index json does not expose a usable session token' do
    get :index, format: :json
    body = response.body
    refute_includes body, @other.session_hash
    assert_includes body, 'expiry'
  end

  test 'show json does not expose a usable session token' do
    get :show, id: @other.id, format: :json
    refute_includes response.body, @other.session_hash
  end

  test 'destroy force-terminates a login' do
    assert_difference 'Session.count', -1 do
      delete :destroy, id: @other.id
    end
    assert_response :redirect
  end

  # create/new/edit/update are not routed on purpose: hand-minting a Session row
  # would bypass the password check entirely.
  test 'minting a session by hand is not routable' do
    assert_raises(ActionController::UrlGenerationError) { post :create, session: { user_id: @admin.id } }
    assert_raises(ActionController::UrlGenerationError) { get :new }
    assert_raises(ActionController::UrlGenerationError) { get :edit, id: @other.id }
  end
end
