require 'test_helper'

# DiskSpace backs both the disk_utilization job and archive pruning, so its
# failure mode matters as much as its arithmetic: a bogus reading must never
# look like "plenty of room".
class DiskSpaceTest < ActiveSupport::TestCase
  test 'measure reports the filesystem holding the path' do
    total, available = DiskSpace.measure(Rails.root.to_s)
    assert total && total.positive?, 'expected a real total for the test filesystem'
    assert available >= 0 && available <= total
  end

  test 'measure follows the mount, not the root filesystem' do
    # The point of the extraction: offline_storage may live on another mount, so
    # grepping df for `/` reports the wrong disk. /tmp is a separate mount on
    # some hosts and the same one on others, so assert only that the call is
    # answered for the path given and is self-consistent.
    total, available = DiskSpace.measure('/tmp')
    assert total && total.positive?
    assert available <= total
  end

  test 'measure returns nil for a path that does not exist' do
    assert_nil DiskSpace.measure('/nonexistent/path/for/disk/space/test')
  end

  test 'measure returns nil for nil' do
    assert_nil DiskSpace.measure(nil)
  end

  # Parsing is asserted against exact df text so the malformed-output branch is
  # reachable: a bogus reading must never be mistaken for a measurable disk.
  test 'parse_df_output reads total and available from a -Pk line' do
    out = <<~DF
      Filesystem     1024-blocks      Used Available Capacity Mounted on
      /dev/sda1         100000000  70000000  20000000      78% /mnt/archive
    DF
    assert_equal [100_000_000 * 1024, 20_000_000 * 1024], DiskSpace.parse_df_output(out)
  end

  test 'parse_df_output uses the available column, not free' do
    # Column 3 is Used, column 4 is Available. Reading Used as Available would
    # report a nearly-full disk as nearly-empty.
    out = "Filesystem 1024-blocks Used Available Capacity Mounted on\n" \
          "/dev/sda1  100000000 90000000  10000000      90% /mnt/archive\n"
    _total, available = DiskSpace.parse_df_output(out)
    assert_equal 10_000_000 * 1024, available
  end

  test 'parse_df_output returns nil for truncated output' do
    assert_nil DiskSpace.parse_df_output("Filesystem 1024-blocks Used\n/dev/sda1 100 90")
  end

  test 'parse_df_output returns nil for non-numeric columns' do
    out = "Filesystem 1024-blocks Used Available Capacity Mounted on\n" \
          "/dev/sda1  total  used  avail  90% /mnt/archive\n"
    assert_nil DiskSpace.parse_df_output(out)
  end

  test 'parse_df_output returns nil for empty output' do
    assert_nil DiskSpace.parse_df_output('')
    assert_nil DiskSpace.parse_df_output(nil)
  end

  test 'parse_df_output returns nil when total is zero' do
    out = "Filesystem 1024-blocks Used Available Capacity Mounted on\n" \
          "procfs 0 0 0 - /proc\n"
    assert_nil DiskSpace.parse_df_output(out)
  end

  test 'percent_used sums to a 0..100 range' do
    used = DiskSpace.percent_used(Rails.root.to_s)
    assert used, 'expected the test filesystem to be measurable'
    assert used >= 0 && used <= 100
  end

  test 'percent_used returns nil rather than 0 when unmeasurable' do
    # The old helper's `split(...)[4].to_i` produced 0 on a missed grep, which
    # reads to an operator as an empty disk.
    assert_nil DiskSpace.percent_used('/nonexistent/path/for/disk/space/test')
  end

  test 'diskUtilization reports the archive partition, not root' do
    dir = Dir.mktmpdir('diskutil')
    ENV['DAD_OFFLINE_STORAGE_DIR'] = dir
    used = Event.diskUtilization
    assert used, 'expected a measurement for the archive dir'
    assert_equal DiskSpace.percent_used(dir), used
  ensure
    ENV['DAD_OFFLINE_STORAGE_DIR'] = nil
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  test 'diskUtilization is nil when the archive partition cannot be measured' do
    assert_nil Event.diskUtilization('/nonexistent/path/for/disk/util/test')
  end

  test 'the disk_utilization job says unknown instead of 0% when unmeasurable' do
    original = Event.method(:diskUtilization)
    begin
      Event.define_singleton_method(:diskUtilization) { |_d = nil| nil }
      out = JobHandler::HANDLERS['disk_utilization'].call(nil)
      assert_match(/unknown/, out)
      refute_match(/0%/, out)
    ensure
      Event.define_singleton_method(:diskUtilization, original)
    end
  end

  test 'the disk_utilization job names the partition it measured' do
    dir = Dir.mktmpdir('diskjob')
    ENV['DAD_OFFLINE_STORAGE_DIR'] = dir
    out = JobHandler::HANDLERS['disk_utilization'].call(nil)
    assert_match(/disk utilization \d+%/, out)
    assert_match(/#{Regexp.escape(dir)}/, out)
  ensure
    ENV['DAD_OFFLINE_STORAGE_DIR'] = nil
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  test 'the dashboard helper returns nil rather than a 0% pie when unmeasurable' do
    helper = Class.new { include ApplicationHelper }.new
    original = Event.method(:diskUtilization)
    begin
      Event.define_singleton_method(:diskUtilization) { |_d = nil| nil }
      assert_nil helper.disk_utilization
    ensure
      Event.define_singleton_method(:diskUtilization, original)
    end
  end
end
