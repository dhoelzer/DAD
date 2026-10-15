require 'test_helper'

# Alert#criticality_name and User#has_right?.
#
# criticality_name compared the integer column against the string "4", so a
# Serious alert was labelled Critical. has_right? issued two Right lookups per
# call, and authorized? calls it once per required right per request.
class AlertCriticalityTest < ActiveSupport::TestCase
  def label(criticality)
    Alert.new(criticality: criticality).criticality_name
  end

  test 'every criticality level labels correctly' do
    assert_equal 'Debug', label(0)
    assert_equal 'Informational', label(1)
    assert_equal 'Warning', label(2)
    assert_equal 'Important', label(3)
    assert_equal 'Serious', label(4)
    assert_equal 'Critical', label(5)
  end

  # The bug: criticality is an integer column, so == "4" never matched and 4
  # fell through to the Critical branch.
  test 'an integer 4 is Serious, not Critical' do
    assert_equal 'Serious', label(4)
    refute_equal 'Critical', label(4)
  end

  test 'out-of-range values fall back to Critical' do
    assert_equal 'Critical', label(9)
    assert_equal 'Critical', label(nil)
  end
end

class UserRightLookupTest < ActiveSupport::TestCase
  def build_user(right_names)
    role = Role.create!(name: "rt-#{SecureRandom.hex(6)}", description: 'r')
    right_names.each do |n|
      role.rights << (Right.where(name: n).first || Right.create!(name: n, description: n))
    end
    user = User.create!(username: "ru-#{SecureRandom.hex(6)}", attempts: 0)
    user.roles << role
    user
  end

  def with_query_capture
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*_args, payload|
      next if payload[:name] == 'SCHEMA'
      sql = payload[:sql]
      next if sql =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|PRAGMA|SAVEPOINT|RELEASE)/i
      queries << sql
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test 'Admin satisfies any right' do
    user = build_user(['Admin'])
    assert user.has_right?('Viewer')
    assert user.has_right?('Detective')
    assert user.has_right?('Nonexistent Right')
  end

  test 'a non-admin only holds the rights granted to its role' do
    user = build_user(%w[Viewer Commentator])
    assert user.has_right?('Viewer')
    assert user.has_right?('Commentator')
    refute user.has_right?('Detective')
    refute user.has_right?('Admin')
  end

  test 'has_right? accepts a Right record as well as a name' do
    user = build_user(['Viewer'])
    right = Right.where(name: 'Viewer').first
    assert user.has_right?(right)
    refute user.has_right?(Right.where(name: 'Admin').first)
  end

  # The old implementation ran two Right.where(...).first queries per call.
  test 'repeated checks do not re-query the rights join' do
    user = build_user(%w[Viewer Detective])
    user.has_right?('Viewer')
    queries = with_query_capture do
      5.times { user.has_right?('Detective') }
    end
    rights_queries = queries.select { |q| q =~ /rights|roles_rights|roles_users/i }
    assert_empty rights_queries,
      "rights must be resolved once per user, got: #{rights_queries.inspect}"
  end

  # The memo must not outlive the DB snapshot. reload refreshes attributes but
  # not instance variables set outside the attribute API, so without an explicit
  # reset a reloaded user kept answering from a stale right list.
  test 'reload re-resolves rights after a grant' do
    user = build_user(%w[Viewer])
    refute user.has_right?('Admin')

    admin_role = Role.create!(name: "adm-#{SecureRandom.hex(6)}", description: 'a')
    # find_or_create_by, not `rights << where(...).first || create!`: << binds
    # tighter than ||, so the guard would never apply and the nil would reach
    # the association setter.
    admin_role.rights << Right.find_or_create_by!(name: 'Admin') { |r| r.description = 'Admin' }
    user.roles << admin_role
    user.reload

    assert user.has_right?('Admin'), 'reload must drop the cached right list'
  end

  test 'reload re-resolves rights after a revoke' do
    user = build_user(%w[Viewer])
    assert user.has_right?('Viewer')

    user.roles = []
    user.reload

    refute user.has_right?('Viewer'), 'reload must drop the cached right list'
  end
end
