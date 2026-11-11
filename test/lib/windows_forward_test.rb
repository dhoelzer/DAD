require 'test_helper'
require 'tmpdir'
require_relative '../../lib/windows_forward'
# The real importer, so the end-to-end tests below drive the same code path
# production does rather than a reimplementation of it.
require File.expand_path('../../../import_syslog.rb', __FILE__)
# The forwarder daemon itself. Requiring it is the point: a missing require or a
# typo in a call site inside the script is otherwise invisible to CI, which is
# exactly how import_syslog.rb shipped broken. The script guards its loop with
# `if __FILE__ == $PROGRAM_NAME`, so this defines methods without looping.
require File.expand_path('../../../import_windows_events.rb', __FILE__)

# Record framing, queue handoff, and the end-to-end path from an OpenWEC output
# file to rows in the events table.
#
# The framing tests are the point of this file. OpenWEC's Files driver appends
# exactly one newline per record, which is true for its Json, Nxlog and JsonRaw
# formats but false for Raw, where a rendered Windows message carries literal
# newlines. A tail that assumed one line per record would turn one 4688 into a
# dozen garbage events, and the garbage would be indistinguishable from real
# data once it was in the database.
class WindowsForwardTest < ActiveSupport::TestCase
  FIXTURE_DIR = File.expand_path('../fixtures/windows_events', __dir__)

  def fixture(name)
    File.read(File.join(FIXTURE_DIR, name))
  end

  def setup
    @staging = Dir.mktmpdir('win-staging')
    @queue = Dir.mktmpdir('LogsToProcess')
    EventIngestor.resetCaches
    EventIngestor.bulk_insert_size = 1000
    # System and Service memoize rows in process-local class variables that
    # outlive the per-test transaction rollback, so a later test would be handed
    # an id whose row no longer exists. Same reason as timestamp_parsing_test.
    System.class_variable_set(:@@cached_stuff, Hash.new)
    Service.class_variable_set(:@@cached_stuff, Hash.new)
  end

  def teardown
    [@staging, @queue, @processed].each { |d| FileUtils.remove_entry(d) if d && File.directory?(d) }
  end

  # ---- record framing ----------------------------------------------------

  def test_reads_a_multiline_raw_xml_record_as_one_record
    # 12 physical lines, one event. This is the framing bug.
    path = File.join(@staging, 'out.log')
    File.write(path, fixture('raw_4688_multiline.xml'))

    records = []
    offset = WindowsForward::Reader.new(path).each_record { |r| records << r }
    assert_equal 1, records.size
    assert_equal File.size(path), offset
  end

  def test_reads_one_record_per_line_for_json_formats
    path = File.join(@staging, 'out.log')
    File.write(path, fixture('security_4688.json') + fixture('nxlog_4688.json') + fixture('rawjson_4688.json'))

    records = []
    offset = WindowsForward::Reader.new(path).each_record { |r| records << r }
    assert_equal 3, records.size
    assert_equal File.size(path), offset
  end

  def test_a_half_written_record_is_not_yielded_and_is_resumed
    # The offset must not advance past a record that has not finished, or the
    # rest of it is skipped on the next pass and the event is lost.
    path = File.join(@staging, 'out.log')
    full = fixture('raw_4688_multiline.xml')
    File.write(path, full[0, 400])

    reader = WindowsForward::Reader.new(path)
    first = []
    offset = reader.each_record { |r| first << r }
    assert_equal 0, first.size, 'an incomplete record must not be yielded'
    assert_equal 0, offset

    File.open(path, 'a') { |io| io.write(full[400..]) }
    second = []
    offset2 = reader.each_record(offset) { |r| second << r }
    assert_equal 1, second.size
    assert_equal File.size(path), offset2
  end

  def test_resume_does_not_re_read_completed_records
    path = File.join(@staging, 'out.log')
    full = fixture('raw_4688_multiline.xml')
    File.write(path, fixture('security_4688.json') + full[0, 400])

    reader = WindowsForward::Reader.new(path)
    got = []
    offset = reader.each_record { |r| got << r }
    assert_equal 1, got.size

    File.open(path, 'a') { |io| io.write(full[400..]) }
    got2 = []
    reader.each_record(offset) { |r| got2 << r }
    assert_equal 1, got2.size
    refute_match(/"System"/, got2.first, 'the already-read JSON record was re-read')
  end

  def test_offset_only_advances_past_yielded_records
    path = File.join(@staging, 'out.log')
    File.write(path, fixture('security_4688.json'))
    reader = WindowsForward::Reader.new(path)
    seen_offsets = []
    reader.each_record { |_| seen_offsets << File.size(path) }
    assert_equal [File.size(path)], seen_offsets
  end

  def test_survives_a_record_that_never_terminates
    # A truncated Raw record (crash mid-write, or a non-event line) must not
    # grow the buffer forever or wedge the tail of the file.
    path = File.join(@staging, 'out.log')
    File.write(path, "<Event><System>" + ('z' * (WindowsForward::MAX_RECORD_BYTES + 10)))

    records = []
    offset = WindowsForward::Reader.new(path).each_record { |r| records << r }
    assert_equal 0, records.size
    assert_equal File.size(path), offset, 'the oversized record must be dropped, not retried forever'
  end

  def test_skips_junk_between_records
    path = File.join(@staging, 'out.log')
    File.write(path, "leftover partial line\n" + fixture('security_4688.json'))

    records = []
    WindowsForward::Reader.new(path).each_record { |r| records << r }
    assert_equal 1, records.size
    assert_match(/"System"/, records.first)
  end

  def test_missing_file_reads_as_empty
    offset = WindowsForward::Reader.new(File.join(@staging, 'nope.log')).each_record { |_| }
    assert_equal 0, offset
  end

  # ---- queue handoff -----------------------------------------------------

  def test_flushed_file_is_claimable_by_log_queue
    # The importer only ever sees a file once it is complete, and only if the
    # name is not one LogQueue treats as claimed or as a sidecar.
    writer = WindowsForward::Writer.new(@staging, @queue)
    writer << WindowsEvents.convert(fixture('security_4688.json'))
    name = writer.flush

    refute_nil name
    assert_empty Dir.children(@staging), 'nothing should be left in staging after a flush'
    names = LogQueue.pending(@queue).map { |p| File.basename(p) }
    assert_equal [name], names
  end

  def test_a_partially_written_file_is_never_visible_to_the_importer
    writer = WindowsForward::Writer.new(@staging, @queue)
    writer << WindowsEvents.convert(fixture('security_4688.json'))
    assert_empty LogQueue.pending(@queue), 'unflushed lines must not reach the queue'

    writer.flush
    assert_equal 1, LogQueue.pending(@queue).size
  end

  def test_writer_refuses_staging_and_queue_being_the_same_directory
    # LogQueue.pending globs '*' and excludes only .processing and .offset names,
    # so a .inprogress file written into the queue directory would be claimed and
    # read while still being appended to.
    assert_raises(ArgumentError) do
      WindowsForward::Writer.new(@queue, @queue)
    end
  end

  def test_flush_fsyncs_before_the_rename
    # The rename is what publishes the file; if the bytes are still in the page
    # cache and the host dies, the importer reads a short file and the offset
    # bookkeeping moves past data that was never written.
    writer = WindowsForward::Writer.new(@staging, @queue)
    3.times { |i| writer << "h.local 2024-01-01T00:00:0#{i}.000Z svc eventid=#{i} channel=Security" }
    name = writer.flush
    assert_equal 3, File.readlines(File.join(@queue, name)).size
  end

  def test_flushes_at_the_configured_line_count
    writer = WindowsForward::Writer.new(@staging, @queue, max_lines: 2)
    5.times { |i| writer << "h.local 2024-01-01T00:00:0#{i}.000Z svc eventid=#{i} channel=Security" }
    writer.flush
    assert_equal 3, Dir.children(@queue).size
  end

  # ---- offset persistence ------------------------------------------------

  def test_offset_round_trips
    path = File.join(@staging, 'out.offset')
    assert_equal 0, WindowsForward::Offset.read(path)
    WindowsForward::Offset.write(path, 4242)
    assert_equal 4242, WindowsForward::Offset.read(path)
  end

  def test_garbage_offset_reads_as_zero
    path = File.join(@staging, 'out.offset')
    File.write(path, 'not a number')
    assert_equal 0, WindowsForward::Offset.read(path)
  end

  # ---- end to end --------------------------------------------------------
  #
  # Through the real queue and the real importer, into Postgres. This is what
  # proves the converted line is not just well-formed to a unit test but is
  # accepted by stage_event's own field splitting, and that the host, service and
  # generated columns land where the UI reads them.

  # Every fixture except the three deliberately-broken ones converts, so the
  # importer should see exactly this many lines and skip none.
  INGESTABLE_FIXTURES = 7

  def test_openwec_records_reach_the_database
    before = Event.count
    lines = ingest_all_fixtures

    assert_equal INGESTABLE_FIXTURES, lines,
                 'every valid fixture must convert to exactly one ingestible line'
    assert_equal before + INGESTABLE_FIXTURES, Event.count
  end

  def test_no_line_was_skipped_by_the_importer
    # A converted line the importer then rejects is the failure mode this guards:
    # the converter and stage_event disagree about the record shape. process_logs
    # counts skips, and a non-zero count means disagreement.
    before = Statistic.where(type_id: 2).count
    lines = ingest_all_fixtures
    assert_equal INGESTABLE_FIXTURES, lines
    assert_equal before, Statistic.where(type_id: 2).count,
                 'the importer skipped a converted line'
  end

  def test_converted_event_lands_on_the_right_system_service_and_timestamp
    ingest_all_fixtures

    event = Event.where("hunks like '%eventid=4688%'")
                 .where("hunks like '%win10.windomain.local%'")
                 .where("hunks like '%record=114689%'")
                 .first
    refute_nil event, 'the Json 4688 fixture should have produced an event'

    assert_equal 'win10.windomain.local', event.system.address
    assert_equal 'microsoft-windows-security-auditing', event.service.name
    assert_equal 2022, event.generated.year
    assert_equal 12, event.generated.month
    assert_equal 14, event.generated.day
    assert_equal 16, event.generated.hour
    assert_equal 6, event.generated.min
  end

  def test_raw_xml_event_lands_on_a_different_host_and_event_id
    ingest_all_fixtures

    event = Event.where("hunks like '%eventid=4720%'").first
    refute_nil event
    assert_equal 'dc01.corp.example.com', event.system.address
    assert_equal 2024, event.generated.year
  end

  def test_multiline_raw_record_produces_exactly_one_event
    before = Event.count
    path = File.join(@staging, 'one.log')
    File.write(path, fixture('raw_4688_multiline.xml'))
    tail_into_queue(path, 0)

    created = Event.where("hunks like '%record=114690%'")
    assert_equal 1, created.count, 'one Windows event must produce one row, not one per message line'
    assert_equal before + 1, Event.count
  end

  def test_event_fields_are_indexed_as_words
    ingest_all_fixtures

    event = Event.where("hunks like '%eventid=4720%'").first
    refute_nil event
    texts = event.words.map(&:text)
    assert_includes texts, 'eventid'
    assert_includes texts, '4720'
    assert_includes texts, 'svc-backup'
  end

  def test_malformed_records_never_reach_the_queue
    # Dropping at conversion keeps the count honest and keeps garbage out of the
    # database; if it reached the queue it would be counted as an ingest failure
    # and inflate the failure Statistic.
    ingest_all_fixtures
    assert_equal 0, Event.where("hunks like '%x.local%'").count
  end

  def test_ingesting_twice_resumes_from_the_offset_and_adds_nothing
    path = File.join(@staging, 'out.log')
    File.write(path, fixture('security_4688.json'))

    offset = tail_into_queue(path, 0)
    first = Event.where("hunks like '%record=114689%'").count

    tail_into_queue(path, offset)
    second = Event.where("hunks like '%record=114689%'").count

    assert_equal first, second, 're-reading the same file must not duplicate events'
    assert_equal 1, first
  end

  # ---- the daemon script -------------------------------------------------
  #
  # convert_pass is import_windows_events.rb's own loop body. The script reads
  # its paths from the environment per pass rather than freezing them at load,
  # which is what lets these drive it against a scratch tree.

  def with_daemon_paths(input)
    saved = ENV.to_h.slice('WINDOWS_INPUT', 'WINDOWS_STAGING', 'WINDOWS_QUEUE', 'WINDOWS_MAX_LINES')
    ENV['WINDOWS_INPUT'] = input
    ENV['WINDOWS_STAGING'] = @staging
    ENV['WINDOWS_QUEUE'] = @queue
    ENV['WINDOWS_MAX_LINES'] = '5000'
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  def test_convert_pass_enqueues_and_records_the_offset
    input = File.join(@staging, 'openwec.log')
    File.write(input, fixture('security_4688.json') + fixture('raw_4720.xml'))

    with_daemon_paths(input) do
      writer = WindowsForward::Writer.new(staging_dir, queue_dir)
      assert_equal 2, convert_pass(writer)
      assert_equal 1, LogQueue.pending(queue_dir).size
      assert_equal File.size(input), WindowsForward::Offset.read("#{input}.dad-offset")
    end
  end

  def test_convert_pass_resumes_and_does_not_re_enqueue
    input = File.join(@staging, 'openwec.log')
    File.write(input, fixture('security_4688.json'))

    with_daemon_paths(input) do
      writer = WindowsForward::Writer.new(staging_dir, queue_dir)
      convert_pass(writer)
      assert_equal 1, Dir.children(queue_dir).size

      File.open(input, 'a') { |io| io.write(fixture('raw_4720.xml')) }
      assert_equal 1, convert_pass(writer)
      assert_equal 2, Dir.children(queue_dir).size
    end
  end

  def test_offset_is_written_after_the_file_is_published
    # If the offset moved first and the process died before the rename, the next
    # pass would start past lines that were never enqueued and those events would
    # be gone. Ordering the other way round only ever duplicates.
    input = File.join(@staging, 'openwec.log')
    File.write(input, fixture('security_4688.json'))

    with_daemon_paths(input) do
      writer = WindowsForward::Writer.new(staging_dir, queue_dir)
      convert_pass(writer)
      assert_equal File.size(input), WindowsForward::Offset.read("#{input}.dad-offset")
      assert_equal 1, LogQueue.pending(queue_dir).size,
                   'the file must be published as well as the offset advanced'
    end
  end

  def test_daemon_end_to_end_into_the_database
    input = File.join(@staging, 'openwec.log')
    File.write(input, fixture('nxlog_7036.json'))

    with_daemon_paths(input) do
      writer = WindowsForward::Writer.new(staging_dir, queue_dir)
      convert_pass(writer)
      drain_queue
    end

    event = Event.where("hunks like '%eventid=7036%'").first
    refute_nil event, 'the daemon path must produce a row, not just a queue file'
    assert_equal 'file01.corp.example.com', event.system.address
  end

  private

  # Runs the full tail -> convert -> queue -> import path over every fixture,
  # returning the number of lines the importer accepted.
  def ingest_all_fixtures
    path = File.join(@staging, 'all.log')
    File.write(path, Dir[File.join(FIXTURE_DIR, '*')].sort.map { |f| File.read(f) }.join)
    tail_into_queue(path, 0)
    @ingested_lines
  end

  def tail_into_queue(path, resume)
    writer = WindowsForward::Writer.new(@staging, @queue)
    offset = WindowsForward::Reader.new(path).each_record(resume) do |record|
      line = WindowsEvents.convert(record)
      writer << line unless line.nil?
    end
    writer.flush
    drain_queue
    offset
  end

  # The real importer pass: claim, checkpoint, batch, move to ProcessedLogs.
  # The line count is stashed because tail_into_queue's own return value is the
  # read offset the resume tests need.
  def drain_queue
    @processed ||= Dir.mktmpdir('ProcessedLogs')
    @ingested_lines = process_logs(@queue, @processed)
  end
end
