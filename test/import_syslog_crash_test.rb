require 'test_helper'
require 'sqlite3'
require File.expand_path('../../lib/log_queue.rb', __FILE__)

# Crash-then-reclaim, end to end.
#
# Reclaim used to re-read an abandoned .processing file from byte 0. Rows the
# dead process had already committed were therefore inserted a second time:
# a 6-line file that died after committing 2 rows ended with those 2 rows
# duplicated. Nothing covered this -- the in-process suite takes the inline
# write branch, and no test ever drove a second run against a database a first
# run had already written to.
#
# Runs are subprocesses with RAILS_ENV=development so the threaded INSERT path
# is the one under test, matching event_ingest_flush_test.rb.
#
# The database is created by run 1 and reused by run 2. It must NOT be rebuilt
# between them: db/schema.rb uses force: :cascade, so reloading it silently
# drops run 1's rows and makes any duplicate disappear. An earlier probe made
# exactly that mistake and reported a false pass.
class ImportSyslogCrashTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  def setup
    @db = Tempfile.new(['reclaim', '.sqlite3'])
    @db.close
    @queue = Dir.mktmpdir('LogsToProcess')
    @processed = Dir.mktmpdir('ProcessedLogs')
  end

  def teardown
    @db.unlink rescue nil
    [@queue, @processed].each do |d|
      FileUtils.remove_entry(d) if d && File.directory?(d)
    end
  end

  def write_log(name, count)
    lines = (1..count).map do |i|
      format('1.1.1.1 Jun 1 00:00:%02d host svc[1]: probe line %d', i, i)
    end
    File.binwrite(File.join(@queue, name), "#{lines.join("\n")}\n")
  end

  # Boots the app, optionally builds the schema, loads the importer script, and
  # runs +body+. RAILS_ENV=development selects the threaded writer.
  def run_importer(body, build_schema:, env: {})
    boot = "require './config/environment'; " \
           "require './import_syslog.rb'; "
    # import_syslog.rb only broadcasts Rails.logger to stdout inside its
    # __FILE__ == $PROGRAM_NAME block, which requiring the file skips. Do it here
    # so tests can assert on what the importer *logs* -- the same thing an
    # operator sees in the journal.
    boot += "Rails.logger = ActiveSupport::BroadcastLogger.new(" \
            "Rails.logger, ActiveSupport::Logger.new($stdout)); "
    boot += "load 'db/schema.rb'; Event.resetCaches; " if build_schema
    out = IO.popen(
      { 'RAILS_ENV' => 'development',
        'DATABASE_URL' => "sqlite3:#{@db.path}",
        'SECRET_KEY_BASE' => 'x' * 32,
        'QUEUE_DIR' => @queue,
        'PROCESSED_DEST' => @processed }.merge(env),
      [RUBY, '-e', "#{boot}#{body}"],
      err: %i[child out], &:read)
    [out, $?.exitstatus]
  end

  # Crashes the process part-way through a file.
  #
  # +drain_at+ makes the run checkpoint deterministically at that line by
  # flushing and joining before dying, so the sidecar is known to be on disk
  # when the process goes away. exit! bypasses every rescue and at_exit hook,
  # which is what a real kill looks like.
  CRASH = <<~'PATCH'
    CRASH_AT = ENV['CRASH_AT'].to_i
    DRAIN_AT = ENV['DRAIN_AT'].to_i
    $seen = 0
    Event.singleton_class.send(:alias_method, :storeEvent_orig, :storeEvent)
    Event.define_singleton_method(:storeEvent) do |line, position = nil|
      $seen += 1
      storeEvent_orig(line, position)
      # Drain after the line is staged, so DRAIN_AT names the last line whose
      # rows are known committed.
      if DRAIN_AT > 0 && $seen == DRAIN_AT
        Event.flush_and_wait
        $stdout.puts "DRAINED at #{$seen}"
      end
      if $seen > CRASH_AT
        $stdout.puts "DYING at #{$seen}"
        $stdout.flush
        exit! 2
      end
    end;
  PATCH

  # Reads the subprocess database directly. ActiveRecord::Base here points at
  # the test database, which holds fixtures and none of the subprocess writes.
  def hunks
    db = SQLite3::Database.new(@db.path)
    rows = db.execute('select hunks from events order by id').map { |r| r[0] }
    db.close
    rows
  end

  def duplicate_count(values)
    values.select { |v| values.count(v) > 1 }.uniq.size
  end

  test 'reclaim after a crash does not re-insert committed rows' do
    write_log('sample.log', 6)

    # Run 1: commit lines 1-2 durably, then die before line 3.
    out, status = run_importer(
      "#{CRASH} Event.instance_variable_set(:@bulk_insert_size, 2); " \
      "process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])",
      build_schema: true, env: { 'CRASH_AT' => '2', 'DRAIN_AT' => '2' })
    assert_equal 2, status, "expected the injected crash, got: #{out}"
    assert_match(/DRAINED at 2/, out)
    assert_match(/DYING at 3/, out)

    first = hunks
    assert_equal 2, first.size, 'run 1 must have committed exactly two rows'

    # The abandoned file and its offset sidecar are what run 2 resumes from.
    assert File.exist?(File.join(@queue, 'sample.log.processing')),
      'a crashed run must leave the file claimed'
    assert File.exist?(File.join(@queue, 'sample.log.processing.offset')),
      'a crashed run must leave a checkpoint to resume from'

    # Run 2: same database, no schema reload.
    out, status = run_importer(
      "Event.instance_variable_set(:@bulk_insert_size, 2); " \
      "process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])",
      build_schema: false)
    assert_equal 0, status, "run 2 should finish cleanly, got: #{out}"
    assert_match(/Reclaiming abandoned sample.log/, out)

    all = hunks
    assert_equal 6, all.size, "expected 6 rows, got #{all.size}: #{all.inspect}"
    assert_equal 0, duplicate_count(all),
      "reclaim re-inserted rows: #{all.inspect}"
    assert_equal [], Dir.children(@queue), 'queue must be empty afterwards'
    assert_equal ['sample.log'], Dir.children(@processed)
  end

  # A crash with a batch still in flight is the at-least-once window: the batch
  # may commit after the last checkpoint was written. Bounded to one batch, and
  # it must never lose a line.
  test 'reclaim never loses lines when a batch was in flight' do
    write_log('sample.log', 6)

    _out, status = run_importer(
      "#{CRASH} Event.instance_variable_set(:@bulk_insert_size, 2); " \
      "process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])",
      build_schema: true, env: { 'CRASH_AT' => '2', 'DRAIN_AT' => '2' })
    assert_equal 2, status

    _out, status = run_importer(
      "Event.instance_variable_set(:@bulk_insert_size, 2); " \
      "process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])",
      build_schema: false)
    assert_equal 0, status

    all = hunks
    assert_equal 0, duplicate_count(all), "lost the at-most-once guarantee: #{all.inspect}"
    assert_equal 6, all.uniq.size, "a line went missing: #{all.inspect}"
  end

  # The old contract: any raise flushed, rewound the checkpoint to the bad line
  # and exited 1. Because the rewind put the bad line back in front of the next
  # run, that run re-read it and exited again -- one unparseable line wedged the
  # pipeline permanently, and nothing restarted the process (RECOMMENDATIONS 5.1
  # and 5.3).
  #
  # The new contract: a StandardError on one line is logged, counted, and skipped.
  # The rest of the file is ingested and the file leaves the queue.
  test 'a StandardError on one line is skipped, not fatal' do
    write_log('sample.log', 6)
    body = <<~'PATCH'
      Event.singleton_class.send(:alias_method, :storeEvent_orig, :storeEvent)
      Event.define_singleton_method(:storeEvent) do |line, position = nil|
        raise 'forced line failure' if line.include?('probe line 3')
        storeEvent_orig(line, position)
      end;
      Event.instance_variable_set(:@bulk_insert_size, 2);
      puts "LINES=#{process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])}"
    PATCH
    out, status = run_importer(body, build_schema: true)

    assert_equal 0, status, "a bad line must not stop the pass:\n#{out}"
    assert_includes out, 'LINES=5', 'the other five lines must still be ingested'
    assert_match(/Skipping unprocessable line/, out, 'the skip must be logged')
    assert_match(/probe line 3/, out, 'the offending line must be logged')
    assert_match(/Skipped 1 unprocessable line/, out, 'the pass must report a count')

    # The file is finished, not left claimed in front of the bad line.
    refute File.exist?(File.join(@queue, 'sample.log.processing')),
      'the file must not stay claimed behind a line that will always fail'
    assert File.exist?(File.join(@processed, 'sample.log')),
      'the file must reach ProcessedLogs'
    assert_equal 5, hunks.size, 'exactly the five good lines must be stored'
    refute(hunks.any? { |h| h.include?('probe line 3') },
      'the skipped line must not be stored')
  end

  # Skipping is only safe because a failed line leaves nothing staged. If it left
  # half a row, skipping would corrupt the index rather than lose one record: the
  # word loop appends to @@events_words before the event row is appended, and
  # @@nextEventID is not advanced on the way out.
  test 'a line that fails part-way through staging leaves nothing behind' do
    body = <<~'PATCH'
      Word.singleton_class.send(:alias_method, :find_or_add_orig, :find_or_add)
      Word.define_singleton_method(:find_or_add) do |w|
        raise 'forced failure mid-staging' if w == 'forced-boom-word'
        find_or_add_orig(w)
      end
      Event.instance_variable_set(:@bulk_insert_size, 1);
      # The importer's per-line rescue is what normally catches this; call
      # storeEvent directly here so the test isolates storeEvent's own rollback.
      begin
        Event.storeEvent('1.1.1.1 Jun 1 00:00:01 host svc[1]: forced-boom-word ok', 10)
        puts 'NO_RAISE'
      rescue RuntimeError => e
        puts "RAISED=#{e.message}"
      end
      Event.storeEvent('1.1.1.1 Jun 1 00:00:02 host svc[1]: good line here', 20)
      Event.flush_and_wait
      puts "EVENTS=#{Event.count}"
      orphans = Event.connection.execute('select count(*) as c from events_words ' +
        'where event_id not in (select id from events)').first['c']
      puts "ORPHANS=#{orphans}"
      puts "IDS=#{Event.order(:id).pluck(:id).join(',')}"
    PATCH
    out, status = run_importer(body, build_schema: true)

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'RAISED=forced failure mid-staging',
      'storeEvent must re-raise after rolling back, so the caller can count the skip'
    assert_includes out, 'EVENTS=1', 'the failing line must contribute no event row'
    assert_includes out, 'ORPHANS=0',
      'a partially staged line must not leave events_words rows for a missing event'
    assert_includes out, 'IDS=1',
      'the next line must not collide with an id the failed line consumed'
  end

  # Non-StandardError still stops the run and rewinds, so a genuinely fatal
  # condition is not papered over. This is the surviving half of the old test.
  test 'a non-StandardError still stops the run and rewinds the checkpoint' do
    write_log('sample.log', 6)
    body = <<~'PATCH'
      Event.singleton_class.send(:alias_method, :storeEvent_orig, :storeEvent)
      Event.define_singleton_method(:storeEvent) do |line, position = nil|
        raise NotImplementedError, 'forced fatal failure' if line.include?('probe line 3')
        storeEvent_orig(line, position)
      end;
      Event.instance_variable_set(:@bulk_insert_size, 2);
      process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])
    PATCH
    out, status = run_importer(body, build_schema: true)

    refute_equal 0, status, "a fatal error must still stop the pass:\n#{out}"
    assert_match(/Fatal error processing/, out, 'the fatal case must be logged as such')

    # The file stays claimed with the offending line still ahead of the offset.
    assert File.exist?(File.join(@queue, 'sample.log.processing'))
    offset = LogQueue.read_offset(File.join(@queue, 'sample.log.processing'))
    refute_equal 0, offset, 'the checkpoint should have advanced past line 1'
    remaining = File.binread(File.join(@queue, 'sample.log.processing'))[offset..-1]
    assert_match(/probe line 3/, remaining,
      'a fatal line must still be ahead of the checkpoint, so a restart retries it')
  end

  # The counter is what distinguishes "the importer is healthy" from "the
  # importer is quietly discarding everything".
  test 'skipped lines are counted as a Statistic series' do
    write_log('sample.log', 4)
    body = <<~'PATCH'
      Event.singleton_class.send(:alias_method, :storeEvent_orig, :storeEvent)
      Event.define_singleton_method(:storeEvent) do |line, position = nil|
        if line.include?('probe line 2') || line.include?('probe line 3')
          raise 'forced line failure'
        end
        storeEvent_orig(line, position)
      end;
      Event.instance_variable_set(:@bulk_insert_size, 2);
      process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])
    PATCH
    _out, status = run_importer(body, build_schema: true)
    assert_equal 0, status

    # Read the subprocess database: ActiveRecord::Base here is the test DB.
    db = SQLite3::Database.new(@db.path)
    rows = db.execute('select type_id, stat from statistics order by id').map { |r| [r[0], r[1]] }
    db.close
    failures = rows.select { |t, _| t == 2 }.map { |_, v| v }
    assert_equal [2], failures, 'one failure row for the pass, counting both skips'
    refute_empty rows.select { |t, _| t == 0 }, 'the lines-processed series is still written'
  end

  # A clean pass must not write a zero row: the series is a signal that lines are
  # being lost, and a zero per pass buries the non-zero ones on the same chart.
  test 'a clean pass writes no failure row' do
    write_log('sample.log', 4)
    body = <<~'PATCH'
      Event.instance_variable_set(:@bulk_insert_size, 2);
      process_logs(ENV['QUEUE_DIR'], ENV['PROCESSED_DEST'])
    PATCH
    _out, status = run_importer(body, build_schema: true)
    assert_equal 0, status

    db = SQLite3::Database.new(@db.path)
    count = db.execute('select count(*) from statistics where type_id = 2').first[0]
    db.close
    assert_equal 0, count, 'a pass with no skips must not write a zero row'
  end
end
