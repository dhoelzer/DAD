require 'test_helper'

# Request-level coverage of the account-administration actions. These routes had
# no tests at all, which is why the defects below survived every previous change.
class UsersAdminTest < ActionController::TestCase
  tests UsersController

  setup do
    @request.env['HTTPS'] = 'on'
    right = Right.create!(name: 'Admin', description: 'admin')
    role = Role.create!(name: "Admins#{SecureRandom.hex(6)}", description: 'admins')
    role.rights << right
    @admin = User.create!(username: "admin#{SecureRandom.hex(6)}", attempts: 0)
    @admin.store_password('secretsauce')
    @admin.roles << role
    Session.create!(user: @admin, expiry: Time.now + 1.hour,
                    session_hash: SecureRandom.hex(16)).tap do |s|
      cookies[:sessionID] = s.session_hash
    end
  end

  def new_user(password)
    u = User.create!(username: "u#{SecureRandom.hex(6)}", attempts: 0)
    u.store_password(password)
    u.save!
    u
  end

  # --- update must not clobber the password when the form omits it ---

  # The edit form renders the password field blank, so submitting it unchanged
  # sends password: "". Re-hashing unconditionally made every edited account's
  # password a hash of the empty string.
  test 'updating without a password leaves the existing password working' do
    victim = new_user('original-pw')

    patch :update, id: victim.id, user: { username: victim.username, first: 'Ada' }

    assert_response :redirect
    victim.reload
    assert_equal 'Ada', victim.first
    assert victim.check_password('original-pw'), 'existing password must still work'
    refute victim.check_password(''), 'must not accept the empty string'
  end

  test 'updating with no password key at all leaves the password intact' do
    victim = new_user('original-pw')
    before = victim.password

    patch :update, id: victim.id, user: { username: victim.username }

    assert_response :redirect
    assert_equal before, victim.reload.password
  end

  test 'updating with a new password changes it' do
    victim = new_user('original-pw')

    patch :update, id: victim.id, user: { username: victim.username, password: 'new-pw-123' }

    assert_response :redirect
    victim.reload
    assert victim.check_password('new-pw-123')
    refute victim.check_password('original-pw')
  end

  # store_password raises rather than truncating, because bcrypt silently ignores
  # bytes past 72. That raise used to escape the action as a 500.
  test 'an over-long password is a form error, not a 500' do
    victim = new_user('original-pw')

    patch :update, id: victim.id, user: { username: victim.username, password: 'A' * 100 }

    assert_response :success # re-renders :edit
    assert victim.check_password('original-pw')
  end

  # user_params permits :password, so it used to be written to the column before
  # store_password ran. When store_password raised, the plaintext stayed saved.
  test 'a rejected update never leaves a plaintext password in the database' do
    victim = new_user('original-pw')
    plaintext = 'B' * 100

    patch :update, id: victim.id, user: { username: victim.username, password: plaintext }

    raw = User.connection.select_value("select password from users where id = #{victim.id}")
    refute_equal plaintext, raw, 'plaintext must never be persisted'
    refute raw.to_s.include?('B' * 20)
  end

  # --- create must not mint an account with an empty password ---

  test 'creating with a blank password is rejected' do
    assert_no_difference 'User.count' do
      post :create, user: { username: "blank#{SecureRandom.hex(6)}", password: '' }
    end
    assert_response :success # re-renders :new
  end

  test 'creating with no password is rejected' do
    assert_no_difference 'User.count' do
      post :create, user: { username: "none#{SecureRandom.hex(6)}" }
    end
    assert_response :success
  end

  test 'creating with a real password succeeds and stores a hash' do
    assert_difference 'User.count' do
      post :create, user: { username: "good#{SecureRandom.hex(6)}", password: 'hunter2pass' }
    end
    created = User.order(:id).last
    assert created.check_password('hunter2pass')
    refute_equal 'hunter2pass', created.password
  end

  # --- destroy must revoke the account's sessions ---

  # gatekeeper resolves a cookie via User.find(session.user_id). A Session row
  # left behind for a deleted user made every request carrying that cookie raise
  # ActiveRecord::RecordNotFound.
  test 'destroying an account revokes its sessions' do
    victim = new_user('victim-pw')
    token = SecureRandom.hex(16)
    Session.create!(user: victim, expiry: Time.now + 1.hour, session_hash: token)

    delete :destroy, id: victim.id

    assert_response :redirect
    assert_nil User.find_by(id: victim.id)
    assert_equal 0, Session.where(user_id: victim.id).count,
                 'sessions must not outlive the account'
  end

  test 'a revoked session no longer authenticates' do
    victim = new_user('victim-pw')
    token = SecureRandom.hex(16)
    Session.create!(user: victim, expiry: Time.now + 1.hour, session_hash: token)

    delete :destroy, id: victim.id
    assert_nil Session.find_by_session_hash(token)

    cookies.delete(:sessionID)
    cookies[:sessionID] = token
    get :index
    assert_response :redirect
    assert_redirected_to logon_users_path
  end

  test 'destroying one account leaves other accounts logged in' do
    keep = new_user('keep-pw')
    keep_token = SecureRandom.hex(16)
    Session.create!(user: keep, expiry: Time.now + 1.hour, session_hash: keep_token)

    gone = new_user('gone-pw')
    gone_token = SecureRandom.hex(16)
    Session.create!(user: gone, expiry: Time.now + 1.hour, session_hash: gone_token)

    delete :destroy, id: gone.id

    refute_nil Session.find_by_session_hash(keep_token),
               'unrelated sessions must survive'
    assert_nil Session.find_by_session_hash(gone_token)
  end
end
