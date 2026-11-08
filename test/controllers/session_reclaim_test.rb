require 'test_helper'

# Abandoned sessions were never reclaimed: gatekeeper deleted an expired row
# only when the cookie owning that row came back. An operator who logged in and
# closed the tab left the row behind forever, so the table grew without bound --
# and that table was scanned on every authenticated request.
#
# do_logon already clears the *logging-in user's* own sessions (deliberate: a
# re-login revokes that account's earlier sessions). That does not help rows
# belonging to anyone else, which is what these tests exercise.
class SessionReclaimTest < ActionController::TestCase
  tests UsersController

  setup do
    @request.env['HTTPS'] = 'on'
    @user = User.create!(username: "reclaim#{SecureRandom.hex(6)}", attempts: 0)
    @user.store_password('secretsauce'); @user.save!
    @colleague = User.create!(username: "gone#{SecureRandom.hex(6)}", attempts: 0)
    Session.delete_all
  end

  test 'logging in reclaims sessions that expired for other accounts' do
    abandoned = Session.create!(user: @colleague, expiry: Time.now - 60,
                                session_hash: SecureRandom.hex(16))

    post :do_logon, params: { user: { username: @user.username, password: 'secretsauce' } }

    refute Session.where(id: abandoned.id).exists?,
      'an abandoned row must be reclaimed by ordinary traffic, not kept forever'
  end

  test 'logging in leaves another account live sessions alone' do
    live = Session.create!(user: @colleague, expiry: Time.now + 3600,
                           session_hash: SecureRandom.hex(16))

    post :do_logon, params: { user: { username: @user.username, password: 'secretsauce' } }

    assert Session.where(id: live.id).exists?,
      'reclaiming expired rows must not sign anyone else out'
  end
end
