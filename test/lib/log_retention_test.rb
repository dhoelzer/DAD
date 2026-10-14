require 'test_helper'
require File.expand_path('../../../lib/log_retention', __FILE__)

class LogRetentionTest < ActiveSupport::TestCase
  DAY = 24 * 3600

  def setup
    @dir = Dir.mktmpdir('processed_logs')
    @now = Time.now
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  # Creates a file with an explicit mtime so "age" does not depend on how long
  # the test took to run.
  def make_file(rel, age_seconds, size = 10)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, 'x' * size)
    mtime = @now - age_seconds
    File.utime(mtime, mtime, path)
    path
  end

  def purge(max_age = 7 * DAY)
    LogRetention.purge(@dir, max_age: max_age, now: @now)
  end

  test 'deletes files past retention and keeps newer ones' do
    old = make_file('old.log', 8 * DAY)
    fresh = make_file('new.log', 60)

    result = purge

    refute File.exist?(old), 'a file past retention must be removed'
    assert File.exist?(fresh), 'a file inside retention must survive'
    assert_equal 1, result.deleted
  end

  test 'the boundary deletes exactly-max-age and keeps one second inside' do
    at_limit = make_file('edge.log', 7 * DAY)
    just_inside = make_file('edge2.log', (7 * DAY) - 1)

    purge

    refute File.exist?(at_limit)
    assert File.exist?(just_inside)
  end

  test 'recurses into subdirectories' do
    nested = make_file('2026/10/old.log', 30 * DAY)
    purge
    refute File.exist?(nested)
  end

  test 'reports the bytes reclaimed' do
    make_file('big.log', 30 * DAY, 4096)
    result = purge
    assert_equal 1, result.deleted
    assert_equal 4096, result.bytes
  end

  test 'a missing directory is not an error' do
    result = LogRetention.purge(File.join(@dir, 'nope'), max_age: 1, now: @now)
    assert_equal 0, result.deleted
  end

  test 'never deletes through a symlink' do
    outside_dir = Dir.mktmpdir('outside')
    outside = File.join(outside_dir, 'secret.log')
    File.binwrite(outside, 'do not delete me')
    mtime = @now - 30 * DAY
    File.utime(mtime, mtime, outside)
    File.symlink(outside, File.join(@dir, 'link.log'))

    begin
      purge
      assert File.exist?(outside), 'purge must not follow a symlink out of the tree'
    ensure
      FileUtils.remove_entry(outside_dir)
    end
  end

  test 'leaves directories in place even when they are old' do
    sub = File.join(@dir, 'nested')
    FileUtils.mkdir_p(sub)
    mtime = @now - 30 * DAY
    File.utime(mtime, mtime, sub)

    purge
    assert File.directory?(sub)
  end

  test 'an unreadable subdirectory does not abort the purge' do
    skip 'running as root, which bypasses directory permissions' if Process.uid.zero?

    unreadable = File.join(@dir, 'locked')
    FileUtils.mkdir_p(unreadable)
    victim = make_file('old.log', 30 * DAY)
    FileUtils.chmod(0o000, unreadable)

    begin
      result = purge
      refute File.exist?(victim), 'the rest of the tree must still be purged'
      assert_equal 1, result.deleted
    ensure
      FileUtils.chmod(0o755, unreadable)
    end
  end
end
