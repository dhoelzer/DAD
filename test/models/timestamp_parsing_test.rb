require 'test_helper'

# Covers EventIngestor.parse_timestamp and the service-offset bookkeeping that depends
# on it. Ingestion used to recognize only three timestamp spellings, one of
# them gated on a hard-coded 2015-2019 year window, and it located the service
# name at a fixed token index. Both assumptions were wrong for the formats
# rsyslog emits by default.
class TimestampParsingTest < ActionDispatch::IntegrationTest
  def setup
    EventIngestor.resetCaches
    EventIngestor.bulk_insert_size = 1
    # System/Service/Word memoize rows in process-local class variables that
    # outlive the per-test transaction rollback, so a later test would be
    # handed an id whose row no longer exists.
    System.class_variable_set(:@@cached_stuff, Hash.new)
    Service.class_variable_set(:@@cached_stuff, Hash.new)
  end

  # Runs +line+ through the real ingestion path and returns the stored row.
  def ingest(line)
    EventIngestor.storeEvent(line)
    EventIngestor.performPendingInserts
    system = System.find_by(address: line.split[0])
    return nil if system.nil?
    event = Event.where(system_id: system.id).last
    return nil if event.nil?
    [event.generated, Service.find(event.service_id).name]
  end

  test "ISO 8601 with milliseconds and Z" do
    generated, service = ingest('host-a.example.com 2026-06-01T12:34:56.123Z sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  # rsyslog's RFC3339timestamps template omits fractional seconds; the old
  # regex required exactly three digits, so this fell through to the
  # no-year branch and the service landed on a message word.
  test "ISO 8601 without fractional seconds" do
    generated, service = ingest('host-b.example.com 2026-06-01T12:34:56Z sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  # '+' is stripped by storeEvent's sanitizer, splitting the offset into its
  # own token. The offset must be rejoined, and the service must not be read
  # from the orphaned "00:00".
  test "RFC 3339 with a positive offset" do
    generated, service = ingest('host-c.example.com 2026-06-01T12:34:56+00:00 sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  # '-' survives the sanitizer, so this spelling stays a single token.
  test "RFC 3339 with a negative offset normalizes to UTC" do
    generated, service = ingest('host-d.example.com 2026-06-01T12:34:56-05:00 sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 17, 34, 56), generated
    assert_equal 'sshd', service
  end

  # The old fallback parsed this by accident (it joined three tokens and
  # appended a year that DateTime.parse then ignored), but read the service
  # from the wrong index -- the ":" separator -- which tr reduced to "".
  test "ISO date and time as separate tokens" do
    generated, service = ingest('host-j.example.com 2026-06-01 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  test "RFC 3164 with an explicit year inside the old window" do
    generated, service = ingest('host-e.example.com Jun 01 2015 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(2015, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  # The regression this file exists for: the year window was 2014 < y < 2020,
  # so any dated line outside it fell through to the no-year branch, which
  # parsed "jun 01 2026 2026 GMT" and kept the year but zeroed the time.
  test "RFC 3164 with an explicit year outside the old window" do
    generated, service = ingest('host-f.example.com Jun 01 2026 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  test "RFC 3164 with an explicit year before the old window" do
    generated, service = ingest('host-g.example.com Jun 01 1999 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(1999, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  # Classic RFC 3164 has no year, so the service sits at index 4, not the
  # hard-coded 5. Index 5 is the PID, which tr("^a-zA-Z\-_/","") reduces to
  # the empty string -- every classic-syslog event was filed with no service.
  test "classic syslog with no year assumes the current year" do
    generated, service = ingest('host-h.example.com Jun  1 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(Date.today.year, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  test "single-digit day is accepted" do
    generated, service = ingest('host-i.example.com Jun 1 12:34:56 sshd[4242]: login ok')
    assert_equal Time.utc(Date.today.year, 6, 1, 12, 34, 56), generated
    assert_equal 'sshd', service
  end

  test "a line with no recognizable timestamp is counted, not silently dropped" do
    before = EventIngestor.timestamp_parse_failures
    assert_nil ingest('host-k.example.com totally not a timestamp sshd[4242]: login ok')
    assert_equal before + 1, EventIngestor.timestamp_parse_failures
  end

  test "parse_timestamp reports the tokens it consumed" do
    timestamp, consumed = EventIngestor.parse_timestamp(
      %w[2026-06-01t12:34:56.123z sshd 4242], 2026)
    assert_equal 1, consumed
    assert_equal 2026, timestamp.year

    timestamp, consumed = EventIngestor.parse_timestamp(
      %w[2026-06-01t12:34:56 00:00 sshd 4242], 2026)
    assert_equal 2, consumed
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), timestamp.to_time

    timestamp, consumed = EventIngestor.parse_timestamp(
      %w[jun 01 2026 12:34:56 sshd], 2026)
    assert_equal 4, consumed
    assert_equal Time.utc(2026, 6, 1, 12, 34, 56), timestamp.to_time

    timestamp, consumed = EventIngestor.parse_timestamp(%w[jun 1 12:34:56 sshd], 2019)
    assert_equal 3, consumed
    assert_equal Time.utc(2019, 6, 1, 12, 34, 56), timestamp.to_time

    timestamp, consumed = EventIngestor.parse_timestamp(%w[not a timestamp], 2026)
    assert_nil timestamp
    assert_equal 0, consumed
  end
end
