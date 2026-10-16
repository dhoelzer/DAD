require 'test_helper'

# provision.sh runs `rake db:seed` on every Vagrant provision, so seeds have to
# be safe to run more than once. They were not: bare new/save plus an unguarded
# has_and_belongs_to_many append meant two runs produced 2 admin users, 4 roles
# and 10 rights where 1, 2 and 5 were intended -- and the duplicate Admin right
# meant Role.find_by_name could pick either copy.
class SeedsIdempotencyTest < ActiveSupport::TestCase
  def run_seeds
    load Rails.root.join('db', 'seeds.rb')
  end

  def setup
    @saved_admin_password = ENV['DAD_ADMIN_PASSWORD']
    ENV['DAD_ADMIN_PASSWORD'] = 'a-long-test-passphrase'
  end

  def teardown
    ENV['DAD_ADMIN_PASSWORD'] = @saved_admin_password
  end

  # Baseline is taken after the first run, not before it: the suite loads
  # fixtures, so a fresh count would include those and the assertion would be
  # about fixtures rather than about seeds.
  test 'seeding twice leaves one of each record' do
    run_seeds
    first = [User.count, Role.count, Right.count, Job.count]
    run_seeds
    second = [User.count, Role.count, Right.count, Job.count]

    assert_equal first, second,
      'a second seed run must not add users, roles, rights or jobs'
    %w[Admin Viewer Commentator Taskmaster Detective].each do |name|
      assert_equal 1, Right.where(name: name).count, "#{name} must exist exactly once"
    end
    assert_equal 1, Role.where(name: 'Administrators').count
    assert_equal 1, Role.where(name: 'Analyst').count
    assert_equal 1, User.where(username: 'admin').count
  end

  # Seeded Jobs are guarded by !Job.exists?(script: ...), so a re-seed must not
  # stack up duplicate scheduled work. A duplicate Job row would run the handler
  # twice per cycle forever.
  test 'seeding twice leaves one of each seeded job' do
    run_seeds
    run_seeds
    %w[tune_dashboard_feed].each do |script|
      assert_equal 1, Job.where(script: script).count, "#{script} must be seeded exactly once"
    end
    if EventPartitioning.supported?
      assert_equal 1, Job.where(script: 'maintain_event_partitions').count
    end
  end

  # rights_roles has no unique index, so the join table is where duplication
  # actually shows up first.
  test 'seeding twice does not duplicate role/right pairs' do
    run_seeds
    first = ActiveRecord::Base.connection.select_value('select count(*) from rights_roles')
    run_seeds
    second = ActiveRecord::Base.connection.select_value('select count(*) from rights_roles')

    assert_equal first, second, 'the join table must not grow on a re-seed'
    admins = Role.find_by!(name: 'Administrators')
    analyst = Role.find_by!(name: 'Analyst')
    assert_equal 1, admins.rights.count, 'Administrators holds Admin once'
    assert_equal 4, analyst.rights.count, 'Analyst holds its four rights once'
  end

  test 'the admin keeps the Administrators role and the seeded password' do
    run_seeds
    admin = User.find_by(username: 'admin')

    refute_nil admin, 'the admin user must be seeded'
    assert admin.roles.exists?(name: 'Administrators')
    assert admin.check_password('a-long-test-passphrase'),
      'the seeded password must be the one DAD_ADMIN_PASSWORD supplied'
  end

  # A re-provision must not undo a password change made after first sign-in.
  test 'a re-seed does not reset a changed admin password' do
    run_seeds
    admin = User.find_by(username: 'admin')
    admin.store_password('changed-by-the-operator')
    admin.save!

    run_seeds

    assert admin.reload.check_password('changed-by-the-operator'),
      're-seeding must not reset the admin password'
    refute admin.check_password('a-long-test-passphrase')
  end

  test 'seeding refuses to run without DAD_ADMIN_PASSWORD' do
    ENV['DAD_ADMIN_PASSWORD'] = nil

    assert_raises(RuntimeError) { run_seeds }
  end
end
