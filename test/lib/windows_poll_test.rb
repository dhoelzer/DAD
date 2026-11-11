require 'test_helper'
require_relative '../../lib/windows_poll'

# WindowsPoll over a real wevtutil envelope.
#
# The fixture under test/fixtures/windows_poll/ is an <Events> document wrapping
# the same two real Windows records the OpenWEC converter tests pin, because that
# is literally what `wevtutil qe /e:xml` writes to stdout. What these tests cover
# is the part the converter tests cannot: splitting the envelope into records,
# the delta query that stops every poll re-ingesting the whole channel, and
# per-channel failure isolation.
class WindowsPollTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path('../fixtures/windows_poll/wevtutil_application.xml', __dir__)

  # Stands in for the WinRM transport: there is no Windows host in CI, and the
  # logic under test is envelope parsing and failure handling, not the wire.
  class FakeTransport
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def read_channel(channel, since)
      @calls << [channel, since]
      response = @responses[channel]
      raise response if response.is_a?(Exception)
      response
    end
  end

  class BufferWriter
    attr_reader :lines

    def initialize; @lines = []; end
    def <<(line); @lines << line; end
    def flush; @lines; end
  end

  def target(attrs = {})
    priority = PollingPriority.create!(name: "T-#{SecureRandom.hex(4)}",
                                       rank: PollingPriority.maximum(:rank).to_i + 1,
                                       min_interval_secs: 60, max_interval_secs: 300)
    WindowsTarget.create!({
      address: 'win10.windomain.local',
      polling_priority: priority,
      event_logs: 'Application,System',
      username: 'poll@example.com',
    }.merge(attrs))
  end

  def envelope
    File.read(FIXTURE)
  end

  # ---- envelope parsing --------------------------------------------------

  test 'splits a wevtutil Events envelope into one staging line per record' do
    writer = BufferWriter.new
    count = WindowsPoll.enqueue(envelope, writer)

    assert_equal 2, count
    assert_equal 2, writer.lines.size
    # Both records carry their real host, taken from <Computer>, in document
    # order: the fixture is the 4720 record first, then the 4688 one.
    # Hostnames are lower-cased on the way into the staging line, matching how
    # the ingestor treats a host token.
    assert_match(/^dc01\.corp\.example\.com /, writer.lines[0])
    assert_match(/^win10\.windomain\.local /, writer.lines[1])
  end

  test 'the converted records keep the fields the importer needs' do
    writer = BufferWriter.new
    WindowsPoll.enqueue(envelope, writer)

    assert_includes writer.lines[0], 'eventid=4720'
    assert_includes writer.lines[0], 'channel=Security'
    assert_includes writer.lines[0], 'data_targetusername=svc-backup'
    assert_includes writer.lines[0], 'data_subjectusername=admin'
    assert_includes writer.lines[0], 'userid=S-1-5-21-1000-2000-3000-512'
    assert_includes writer.lines[1], 'eventid=4688'
    assert_includes writer.lines[1], 'data_newprocessname=C:\\Windows\\System32\\cmd.exe'
  end

  test 'an empty or missing document yields nothing' do
    writer = BufferWriter.new
    assert_equal 0, WindowsPoll.enqueue(nil, writer)
    assert_equal 0, WindowsPoll.enqueue('', writer)
    assert_equal 0, WindowsPoll.enqueue('   ', writer)
    assert_empty writer.lines
  end

  test 'a document with no Event children yields nothing' do
    writer = BufferWriter.new
    assert_equal 0, WindowsPoll.enqueue('<Events></Events>', writer)
    assert_empty writer.lines
  end

  # A DTD in XML that a remote host controls is an XXE attempt. The converter
  # refuses one; the poller must not hand it a parser that accepts one.
  test 'refuses a DTD in host-supplied XML' do
    hostile = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
      <Events><Event><System><Computer>&xxe;</Computer></System></Event></Events>
    XML
    writer = BufferWriter.new
    WindowsPoll.enqueue(hostile, writer)

    assert_empty writer.lines
    refute_includes writer.lines.join, 'root:'
  end

  # ---- delta query -------------------------------------------------------

  test 'the first poll reads a bounded window rather than the whole channel' do
    query = WindowsPoll.delta_query(nil)

    assert_match(/TimeCreated\[timediff\(@SystemTime\) <= \d+\]/, query)
    assert_equal 86_400_000, query[/<= (\d+)/, 1].to_i
  end

  test 'a later poll reads only since the last one, plus an overlap' do
    since = Time.now - 3_600
    window = WindowsPoll.delta_query(since)[/<= (\d+)/, 1].to_i

    # One hour of gap plus the 60s overlap, within a second of tolerance.
    assert_in_delta 3_660_000, window, 1_000
  end

  test 'the overlap keeps records whose timestamp predates their write' do
    since = Time.now - 10
    window = WindowsPoll.delta_query(since)[/<= (\d+)/, 1].to_i

    # A record timestamped just before the last poll but written after it would
    # fall outside a bare gap; the overlap is what keeps it.
    assert_operator window, :>=, 70_000
  end

  test 'a clock skew into the future still yields a usable window' do
    window = WindowsPoll.delta_query(Time.now + 3_600)[/<= (\d+)/, 1].to_i

    assert_equal 86_400_000, window
  end

  # ---- polling a target --------------------------------------------------

  test 'poll reads every configured channel and queues what it finds' do
    transport = FakeTransport.new('Application' => envelope, 'System' => '<Events></Events>')
    writer = BufferWriter.new

    result = WindowsPoll.poll(target, writer: writer, transport: transport)

    assert_equal %w[Application System], transport.calls.map(&:first)
    assert_equal 2, result.event_count
    assert_equal 2, writer.lines.size
    assert_equal 'ok', result.status
  end

  test 'a channel that fails does not lose the other channels' do
    transport = FakeTransport.new(
      'Application' => RuntimeError.new('Access is denied because the Y service was not started.'),
      'System' => envelope)
    writer = BufferWriter.new

    result = WindowsPoll.poll(target, writer: writer, transport: transport)

    assert_equal 2, result.event_count, 'the System channel still came through'
    assert_match(/partial/, result.status)
    assert_match(/Access is denied/, result.detail)
  end

  test 'poll flushes once so the importer only ever sees a complete file' do
    transport = FakeTransport.new('Application' => envelope, 'System' => envelope)
    writer = BufferWriter.new

    WindowsPoll.poll(target, writer: writer, transport: transport)

    assert_equal 4, writer.lines.size
  end

  test 'poll passes the last poll time as the delta boundary' do
    boundary = Time.now - 7_200
    transport = FakeTransport.new('Application' => '<Events></Events>', 'System' => '<Events></Events>')

    WindowsPoll.poll(target(last_polled_at: boundary), writer: BufferWriter.new, transport: transport)

    # last_polled_at round-trips through Postgres at microsecond precision, so
    # compare to the same precision rather than to the nanosecond Time.now.
    transport.calls.each do |_channel, since|
      assert_in_delta boundary.to_f, since.to_f, 0.001
    end
  end
end
