require 'test_helper'

# Loads the real importer script.
#
# This file exists because import_syslog.rb shipped broken on master: purge_logs
# called LogRetention.purge while the require for log_retention.rb had been lost
# in a merge, and nothing in test/ or features/ ever loaded the script, so CI
# stayed green while the importer died on its first purge. Requiring it here makes
# that class of breakage -- a missing require, a renamed constant, a typo in a
# call site inside the script -- fail the build.
#
# The script guards its loop with `if __FILE__ == $PROGRAM_NAME`, so requiring it
# defines the methods without chdir-ing this process or starting a second
# importer.
require File.expand_path('../../import_syslog.rb', __FILE__)

class ImportSyslogTest < ActiveSupport::TestCase
  def setup
    @queue = Dir.mktmpdir('LogsToProcess')
    @processed = Dir.mktmpdir('ProcessedLogs')
    Event.resetCaches
    # Development/test batch size is 1, which flushes per line and makes the
    # Statistic write race the insert thread on SQLite. One batch keeps it sane.
    Event.instance_variable_set(:@bulk_insert_size, 1000)
  end

  def teardown
    [@queue, @processed].each { |d| FileUtils.remove_entry(d) if d && File.directory?(d) }
  end

  # test/fixtures/events.yml loads two rows, so Event.count is never zero. Every
  # count below is measured as a delta from the fixture baseline.
  def event_delta
    before = Event.count
    yield
    Event.count - before
  end

  def write_log(name, lines)
    File.binwrite(File.join(@queue, name), lines.map { |l| "#{l}\n" }.join)
  end

  def syslog_lines(count)
    (1..count).map do |i|
      format('1.1.1.1 Jun 1 00:00:%02d host svc[1]: probe line %d', i, i)
    end
  end

  # The regression itself: purge_logs referenced LogRetention without the file
  # being required, so the constant did not resolve and the importer exited.
  test 'purge_logs resolves LogRetention and reports a count' do
    old = File.join(@processed, 'old.log')
    File.binwrite(old, 'ancient\n')
    File.utime(Time.now - 30 * 86_400, Time.now - 30 * 86_400, old)

    assert_equal 1, purge_logs(@processed).deleted
    refute File.exist?(old), 'a 30-day-old processed log must be deleted'
  end

  test 'purge_logs leaves recent files alone' do
    recent = File.join(@processed, 'recent.log')
    File.binwrite(recent, 'fresh\n')

    assert_equal 0, purge_logs(@processed).deleted
    assert File.exist?(recent)
  end

  test 'process_logs ingests a queued file and moves it to processed' do
    write_log('one.log', syslog_lines(3))

    delta = event_delta { process_logs(@queue, @processed) }

    assert_equal 3, delta
    assert_equal [], Dir.children(@queue)
    assert_equal ['one.log'], Dir.children(@processed),
      'the file must land under its original name, not its .processing name'
  end

  test 'process_logs reclaims a file abandoned by a dead run' do
    abandoned = File.join(@queue, 'half.log.processing')
    File.binwrite(abandoned, "#{syslog_lines(2).join("\n")}\n")

    delta = event_delta { process_logs(@queue, @processed) }

    assert_equal 2, delta
    assert_equal ['half.log'], Dir.children(@processed)
  end

  test 'process_logs ignores directories in the queue' do
    FileUtils.mkdir_p(File.join(@queue, 'stray'))
    write_log('good.log', syslog_lines(1))

    delta = event_delta { process_logs(@queue, @processed) }
    assert_equal 1, delta
  end

  test 'process_logs on an empty queue is a no-op' do
    delta = event_delta { process_logs(@queue, @processed) }
    assert_equal 0, delta
  end

  # The constants collapsed from PROCESSED_DIR/PROCESSED_LOGS to one name; a
  # second definition would silently re-introduce the split.
  test 'the processed directory is defined once' do
    assert Object.const_defined?(:PROCESSED_DIR)
    refute Object.const_defined?(:PROCESSED_LOGS),
      'PROCESSED_LOGS duplicated PROCESSED_DIR after the merge of #13 and #15'
  end
end
