require 'test_helper'

# The archive free-space floor is set through the Preferences screen. These cover
# the write path end to end: strong parameters, the clamp, and the Admin gate.
#
# The clamp matters here specifically because the form posts a string, and an
# unclamped 1000 would be read back as "keep 1000% of the partition free" -- a
# requirement no filesystem can meet, so pruning would delete every archive.
class PreferencesArchiveFloorTest < ActionController::TestCase
  tests PreferencesController

  setup do
    @request.env['HTTPS'] = 'on'
    @pref = Preference.create!(user_id: 0, created_at: Time.now, updated_at: Time.now)
  end

  def log_in(right_name)
    right = Right.create!(name: right_name, description: right_name)
    role = Role.create!(name: "#{right_name}s#{Time.now.to_i}", description: right_name)
    role.rights << right
    user = User.create!(username: "#{right_name}#{Time.now.to_i}", attempts: 0)
    user.store_password('secretsauce')
    user.roles << role
    session_hash = SecureRandom.hex(16)
    Session.create!(user: user, expiry: Time.now + 1.hour, session_hash: session_hash)
    cookies[:sessionID] = session_hash
    user
  end

  test 'an admin can set the floor through the form' do
    log_in('Admin')
    patch :update, params: { id: @pref.id, preference: { archiveFreeSpacePercent: '20' } }
    assert_response :redirect
    assert_equal 20, @pref.reload.archiveFreeSpacePercent
  end

  test 'an out-of-range value posted by the form is clamped, not stored raw' do
    log_in('Admin')
    patch :update, params: { id: @pref.id, preference: { archiveFreeSpacePercent: '1000' } }
    assert_equal 100, @pref.reload.archiveFreeSpacePercent,
      'an unclamped 1000 would make every archive prunable'
  end

  test 'clearing the field disables pruning' do
    @pref.update!(archiveFreeSpacePercent: 20)
    log_in('Admin')
    patch :update, params: { id: @pref.id, preference: { archiveFreeSpacePercent: '' } }
    assert_nil @pref.reload.archiveFreeSpacePercent
    assert_nil EventPartitionBackup.free_space_percent
  end

  test 'the form renders the field with a warning about unrecoverable pruning' do
    log_in('Admin')
    get :edit, params: { id: @pref.id }
    assert_response :success
    assert_select 'input#preference_archiveFreeSpacePercent'
    assert_match(/unrecoverable/i, response.body)
  end

  # Preferences is Admin-gated in CONTROLLER_RIGHTS; a Viewer must not be able to
  # trigger deletion of archived history.
  test 'a non-admin cannot change the floor' do
    log_in('Viewer')
    patch :update, params: { id: @pref.id, preference: { archiveFreeSpacePercent: '95' } }
    assert_response :redirect
    assert_redirected_to logon_users_path
    assert_nil @pref.reload.archiveFreeSpacePercent
  end
end
