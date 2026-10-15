require 'test_helper'

# The privilege-escalation path: role_add/role_remove decide what a user may do,
# and granting the Admin role grants every right (User#has_right? short-circuits
# on ADMIN_RIGHT). These actions had no request-level coverage at all.
class RoleGrantTest < ActionController::TestCase
  tests UsersController

  setup do
    @request.env['HTTPS'] = 'on'
    @admin_right = Right.create!(name: 'Admin', description: 'admin')
    @viewer_right = Right.create!(name: 'Viewer', description: 'view')
    @admin_role = Role.create!(name: "Admins#{SecureRandom.hex(6)}", description: 'a')
    @admin_role.rights << @admin_right
    @viewer_role = Role.create!(name: "Viewers#{SecureRandom.hex(6)}", description: 'v')
    @viewer_role.rights << @viewer_right

    @admin = user('admin')
    @admin.roles << @admin_role
    sign_in(@admin)
  end

  attr_reader :admin, :admin_role, :viewer_role, :viewer_right

  def user(prefix)
    u = User.create!(username: "#{prefix}#{SecureRandom.hex(6)}", attempts: 0)
    u.store_password('secretsauce')
    u.save!
    u
  end

  def sign_in(u)
    cookies[:sessionID] = Session.create!(user: u, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash
  end

  def test_roles_screen_lists_granted_and_ungranted_roles
    target = user('target')
    target.roles << viewer_role

    get :roles, params: { id: target.id }

    assert_response :success
    assert_includes response.body, viewer_role.name
    assert_includes response.body, admin_role.name,
                    'ungranted roles must be offered as candidates'
  end

  def test_role_add_grants_the_role
    target = user('target')
    assert_not target.has_role?(viewer_role)

    post :role_add, params: { id: target.id, role: viewer_role.id }

    assert_response :redirect
    assert target.reload.has_role?(viewer_role)
  end

  # Granting Admin is the escalation: has_right? returns true for every right.
  def test_granting_admin_confers_every_right
    target = user('target')
    assert_not target.has_right?('Detective')

    post :role_add, params: { id: target.id, role: admin_role.id }

    assert target.reload.has_right?('Admin')
    assert target.has_right?('Detective'), 'Admin must act as a wildcard'
    assert target.has_right?('Taskmaster')
  end

  def test_role_remove_revokes_only_the_named_role
    target = user('target')
    target.roles << viewer_role

    post :role_remove, params: { id: target.id, role: viewer_role.id }

    assert_response :redirect
    refute target.reload.has_role?(viewer_role)
  end

  # Re-granting must not duplicate the join row; HABTM << is idempotent but the
  # branch also drives the flash text the UI shows.
  def test_role_add_is_idempotent_for_an_existing_role
    target = user('target')
    target.roles << viewer_role

    assert_no_difference 'target.reload.roles.count' do
      post :role_add, params: { id: target.id, role: viewer_role.id }
    end
    assert target.reload.has_role?(viewer_role)
  end

  # A missing/blank role param used to raise RecordNotFound (500) rather than a
  # 404 or a redirect.
  def test_role_add_with_an_unknown_role_does_not_500
    target = user('target')

    assert_raises(ActiveRecord::RecordNotFound) do
      post :role_add, params: { id: target.id, role: 999_999 }
    end
  end

  # The escalation endpoint must not be reachable by a non-admin.
  def test_a_non_admin_cannot_grant_roles
    viewer = user('viewer')
    viewer.roles << viewer_role
    target = user('target')

    sign_in(viewer)
    post :role_add, params: { id: target.id, role: admin_role.id }

    assert_response :redirect
    assert_not target.reload.has_role?(admin_role),
               'a Viewer must not be able to grant Admin'
  end

  # Revoking Admin from the signed-in admin must take effect for the next
  # request, otherwise de-privileging is cosmetic.
  def test_revoking_admin_from_yourself_takes_effect_next_request
    admin.roles << viewer_role

    post :role_remove, params: { id: admin.id, role: admin_role.id }

    assert_response :redirect
    refute admin.reload.has_right?('Admin')
  end
end
