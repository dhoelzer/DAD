require 'test_helper'

# do_logon read its credentials as params[:user][:username]. That is a chained
# index on a value that is nil whenever the POST carries no `user` key at all, so
# a hand-built request -- a crawler, a scanner, an API client, a form serialized
# differently than expected -- returned 500 instead of being rejected.
#
# A 500 here is worse than merely untidy:
#
#   * It is a denial of service on the login path. Each request renders a full
#     Rails debug page (~110KB in development) and writes a backtrace to the log,
#     and nothing rate-limits it because no user was resolved.
#   * It leaks a stack trace and the app's source to whoever asks.
#   * It is the one action reachable with no session, so it is the highest-value
#     target of its kind.
#
# These tests assert the malformed request is treated the way a wrong password
# already is: no session minted, back to the logon form. They deliberately do not
# pin the flash text -- see the note in test/system/authentication_test.rb about
# authorized? overwriting the notice.
class LogonMalformedPostTest < ActionController::TestCase
  tests UsersController

  setup do
    @request.env['HTTPS'] = 'on'
    @user = User.create!(username: "logonprobe#{SecureRandom.hex(6)}", attempts: 0)
    @user.store_password('secretsauce'); @user.save!
    Session.delete_all
  end

  # The reported shape: no `user` key at all.
  test 'a post with no user params is rejected rather than raising' do
    post :do_logon

    assert_response :redirect
    assert_nil cookies[:sessionID], 'a malformed post must not mint a session'
  end

  # `user` present but empty, and `user` present with the fields missing.
  test 'an empty user hash is rejected rather than raising' do
    post :do_logon, params: { user: {} }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  test 'a user hash missing the password is rejected rather than raising' do
    post :do_logon, params: { user: { username: @user.username } }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  test 'a user hash missing the username is rejected rather than raising' do
    post :do_logon, params: { user: { password: 'secretsauce' } }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  # A nested value of the wrong type. `user[username]=[]` arrives as an Array, and
  # find_by(username: []) raises; the old code would have 500'd here too.
  test 'a nested param of the wrong type is rejected rather than raising' do
    post :do_logon, params: { 'user' => { 'username' => [] } }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  # `user` itself of the wrong type: ?user[]=... arrives as an Array.
  test 'a user param of the wrong type is rejected rather than raising' do
    post :do_logon, params: { 'user' => ['a', 'b'] }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  # A blank username must not reach find_by as something that could match. The
  # integrity migration renamed any blank/NULL username to disabled-account-<id>,
  # so no live row has one; assert that rather than assume it.
  test 'a blank username does not sign anyone in' do
    post :do_logon, params: { user: { username: '', password: 'secretsauce' } }
    assert_response :redirect
    assert_nil cookies[:sessionID]
  end

  # The lockout counter must not be fed by anonymous garbage. Otherwise repeated
  # malformed posts could lock a real account out of the login form.
  test 'a malformed post does not consume an account lockout attempt' do
    before = @user.reload.attempts

    post :do_logon

    assert_equal before, @user.reload.attempts,
      'a request that named no account must not spend that account attempts'
  end

  # Guard the happy path against the same refactor.
  test 'a valid post still signs in' do
    post :do_logon, params: { user: { username: @user.username, password: 'secretsauce' } }

    assert_response :redirect
    refute_nil cookies[:sessionID]
    assert_equal 0, @user.reload.attempts
  end

  # And the wrong-password path, which already worked: it must keep its behaviour
  # of incrementing the counter.
  test 'a wrong password still costs an attempt' do
    before = @user.reload.attempts

    post :do_logon, params: { user: { username: @user.username, password: 'wrong' } }

    assert_response :redirect
    assert_nil cookies[:sessionID]
    assert_equal before + 1, @user.reload.attempts
  end

  # users.attempts is nullable with no column default, and the failure branch of
  # do_logon already guarded it (`@user.attempts = 0 unless @user.attempts`), so a
  # row with nil was expected. The lockout check did `@user.attempts > 3`, and
  # nil > 3 raises -- so such an account could not sign in at all, valid password
  # or not. This is a second 500 on the same public action, reachable by a row
  # written before the counter was always initialized.
  test 'an account with a NULL attempt counter can still sign in' do
    @user.update_column(:attempts, nil)

    post :do_logon, params: { user: { username: @user.username, password: 'secretsauce' } }

    assert_response :redirect
    refute_nil cookies[:sessionID], 'a valid credential must work regardless of the counter'
    assert_equal 0, @user.reload.attempts
  end
end
