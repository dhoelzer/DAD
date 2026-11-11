require 'test_helper'
require_relative '../support/query_plan'

# Two findings about the sessions table.
#
# (1) gatekeeper resolves the :sessionID cookie with
# Session.find_by(session_hash:) on every authenticated request, and there was
# no index on that column -- the plan was a full table SCAN.
#
# (2) An expired row was only deleted when the cookie that owns it came back.
# Close the tab, never return, and the row is permanent. So the table the
# unindexed lookup scans grows without bound.
class SessionIntegrityTest < ActiveSupport::TestCase
  include QueryPlan

  def setup
    Session.delete_all
    @user = User.create!(username: "sess#{SecureRandom.hex(6)}", attempts: 0)
  end

  test 'sessions.session_hash is indexed' do
    on_hash = ActiveRecord::Base.connection.indexes(:sessions).select do |i|
      i.columns.include?('session_hash')
    end
    refute_empty on_hash,
      'session_hash is looked up on every authenticated request and must be indexed'
  end

  test 'session_hash is unique: it is the sole bearer credential' do
    existing = Session.create!(user: @user, expiry: Time.now + 3600,
                               session_hash: SecureRandom.hex(16))
    assert_raises(ActiveRecord::RecordNotUnique) do
      # insert! rather than insert_all: the non-bang version uses
      # ON CONFLICT DO NOTHING and would swallow the collision being asserted.
      Session.insert!({ user_id: @user.id, expiry: Time.now + 3600,
                        session_hash: existing.session_hash })
    end
  end

  # The finding this guards is a plan, not a query: the lookup ran on every
  # authenticated request with no index, so it was a full scan of a table that
  # only ever grew. Asserting on the plan is the only way to catch the index
  # being dropped or renamed, since the query returns correct rows either way.
  test 'the session lookup uses the index rather than scanning the table' do
    plan = explain('SELECT * FROM sessions WHERE session_hash = ?', ['x' * 64])
    assert_match(/Index Scan using \w*session_hash\w*/i, plan,
      "session lookup must use the session_hash index: #{plan}")
    refute_match(/Seq Scan on sessions/i, plan,
      "session lookup must not be a table scan: #{plan}")
  end

  test 'purge_expired removes expired rows and leaves live ones' do
    expired = Session.create!(user: @user, expiry: Time.now - 60,
                              session_hash: SecureRandom.hex(16))
    live = Session.create!(user: @user, expiry: Time.now + 3600,
                           session_hash: SecureRandom.hex(16))

    removed = Session.purge_expired

    assert_operator removed, :>=, 1
    refute Session.where(id: expired.id).exists?, 'expired row must be reclaimed'
    assert Session.where(id: live.id).exists?, 'live session must survive'
  end
end
