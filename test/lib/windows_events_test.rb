require 'test_helper'
require_relative '../../lib/windows_events'

# Converter tests over real Windows event records.
#
# The fixtures under test/fixtures/windows_events/ are captured/reconstructed
# Windows events in each of the four output formats OpenWEC can write. They are
# deliberately not synthetic: the value of these tests is that they pin the
# shapes OpenWEC actually emits, including the field-name differences between
# its Json and Nxlog formats and the 7-9 fractional digits Windows puts in
# TimeCreated.
class WindowsEventsTest < ActiveSupport::TestCase
  FIXTURE_DIR = File.expand_path('../fixtures/windows_events', __dir__)

  def fixture(name)
    File.read(File.join(FIXTURE_DIR, name))
  end

  # The staging line, split the way EventIngestor splits it, so a test that
  # asserts on "field 3" means the same thing the importer means.
  def fields(line)
    line.chomp.split(/ +/)
  end

  # ---- format detection --------------------------------------------------

  def test_detects_each_format
    assert_equal :json,     WindowsEvents.detect(fixture('security_4688.json').strip)
    assert_equal :nxlog,    WindowsEvents.detect(fixture('nxlog_4688.json').strip)
    assert_equal :raw_json, WindowsEvents.detect(fixture('rawjson_4688.json').strip)
    assert_equal :xml,      WindowsEvents.detect(fixture('raw_4720.xml').strip)
  end

  def test_detects_nothing_for_unusable_input
    assert_nil WindowsEvents.detect('')
    assert_nil WindowsEvents.detect('not an event at all')
    assert_nil WindowsEvents.detect('{"nonsense":true}')
    assert_nil WindowsEvents.detect(fixture('malformed.json').strip)
  end

  # ---- Json format -------------------------------------------------------

  def test_json_yields_host_timestamp_service_then_body
    line = WindowsEvents.convert(fixture('security_4688.json'))
    refute_nil line
    parts = fields(line)

    assert_equal 'win10.windomain.local', parts[0]
    assert_equal '2022-12-14T16:06:51.064Z', parts[1]
    assert_equal 'microsoft-windows-security-auditing', parts[2]
    assert_includes line, 'eventid=4688'
    assert_includes line, 'channel=Security'
  end

  def test_json_normalizes_windows_nanoseconds_to_milliseconds_z
    # Windows emits 7 fractional digits here and 9 in the 4625 fixture. Both
    # must land as a single RFC 3339 token with a literal Z, because stage_event
    # replaces '+' with a space, which would split an offset across two tokens
    # and shift the Service field off its offset.
    assert_equal '2022-12-14T16:06:51.064Z', fields(WindowsEvents.convert(fixture('security_4688.json')))[1]
    assert_equal '2024-03-02T09:15:04.928Z', fields(WindowsEvents.convert(fixture('security_4625.json')))[1]
  end

  def test_json_falls_back_to_openwec_ip_address_when_computer_missing
    payload = {
      'System' => { 'EventID' => 4688, 'Channel' => 'Security',
                    'TimeCreated' => '2024-01-01T00:00:00Z',
                    'Provider' => { 'Name' => 'Prov' } },
      'OpenWEC' => { 'IpAddress' => '10.1.2.3' }
    }
    line = WindowsEvents.convert(payload.to_json)
    refute_nil line
    assert_equal '10.1.2.3', fields(line)[0]
  end

  def test_json_uses_channel_as_service_when_provider_absent
    payload = {
      'System' => { 'EventID' => 4688, 'Channel' => 'Windows PowerShell',
                    'TimeCreated' => '2024-01-01T00:00:00Z', 'Computer' => 'h.local' }
    }
    assert_equal 'windows-powershell', fields(WindowsEvents.convert(payload.to_json))[2]
  end

  # ---- Nxlog format ------------------------------------------------------

  def test_nxlog_maps_flattened_field_names
    # OpenWEC's Nxlog format flattens System into the top level and renames
    # several members: Hostname not Computer, EventTime not TimeCreated,
    # SourceName not Provider.Name.
    line = WindowsEvents.convert(fixture('nxlog_7036.json'))
    refute_nil line
    parts = fields(line)
    assert_equal 'file01.corp.example.com', parts[0]
    assert_equal '2024-03-02T09:14:58.000Z', parts[1]
    assert_equal 'service-control-manager', parts[2]
    assert_includes line, 'eventid=7036'
  end

  def test_nxlog_separates_system_fields_from_event_data
    # EventData named fields are flattened alongside System fields in this
    # format, so the split is by known-name list. Getting it wrong would not
    # break parsing, it would silently mislabel which words are searchable.
    line = WindowsEvents.convert(fixture('nxlog_4688.json'))
    refute_nil line
    assert_includes line, 'eventid=4688'
    assert_includes line, 'data_newprocessname=C:\\Windows\\System32\\cmd.exe'
    assert_includes line, 'data_commandline=cmd.exe /c whoami'
  end

  def test_nxlog_does_not_emit_a_field_twice
    line = WindowsEvents.convert(fixture('nxlog_4688.json'))
    keys = line.scan(/([a-z_0-9]+)=/).flatten
    assert_equal keys.uniq, keys, "duplicate keys in: #{line}"
  end

  # ---- Raw XML and JsonRaw -----------------------------------------------

  def test_raw_xml_parses_namespaced_event
    line = WindowsEvents.convert(fixture('raw_4720.xml'))
    refute_nil line
    parts = fields(line)
    assert_equal 'dc01.corp.example.com', parts[0]
    assert_equal '2024-03-02T11:22:33.123Z', parts[1]
    assert_includes line, 'eventid=4720'
    assert_includes line, 'data_targetusername=svc-backup'
  end

  def test_raw_xml_reads_security_userid_attribute
    # <Security UserID="..."/> is an attribute, not element text.
    assert_includes WindowsEvents.convert(fixture('raw_4720.xml')),
                    'userid=S-1-5-21-1000-2000-3000-512'
  end

  def test_raw_xml_without_namespace_still_parses
    # wevtutil and hand-written fixtures emit the Event element with no
    # namespace at all. Matching on local names rather than a hard-coded
    # namespace URI is what makes both work.
    stripped = fixture('raw_4720.xml')
                 .sub(%r{ xmlns='http://schemas\.microsoft\.com/win/2004/08/events/event'}, '')
    line = WindowsEvents.convert(stripped)
    refute_nil line
    assert_equal 'dc01.corp.example.com', fields(line)[0]
  end

  def test_raw_xml_with_multiline_rendered_message_collapses_to_one_line
    # The trap this guards: OpenWEC's Files driver appends exactly one newline
    # per record, but a rendered Windows message (RenderingInfo/Message)
    # contains literal newlines and tabs. A converter that trusted "one line is
    # one record" would emit a dozen garbage events from this one.
    raw = fixture('raw_4688_multiline.xml')
    assert_operator raw.lines.size, :>, 5, 'fixture must be multi-line to be meaningful'

    line = WindowsEvents.convert(raw)
    refute_nil line
    assert_equal 1, line.lines.size
    assert_includes line, 'message=A new process has been created.'
    refute_includes line, "\t"
  end

  def test_jsonraw_unwraps_meta_and_data
    line = WindowsEvents.convert(fixture('rawjson_4688.json'))
    refute_nil line
    parts = fields(line)
    assert_equal 'win10.windomain.local', parts[0]
    assert_includes line, 'data_newprocessname=C:\\Windows\\System32\\whoami.exe'
    assert_includes line, 'client=WIN10$@WINDOMAIN.LOCAL'
  end

  def test_jsonraw_supplies_host_from_meta_when_xml_has_no_computer
    xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>" \
          '<System><EventID>4688</EventID><Channel>Security</Channel>' \
          "<TimeCreated SystemTime='2024-01-01T00:00:00Z'/></System></Event>"
    payload = { 'meta' => { 'IpAddress' => '192.0.2.42' }, 'data' => xml }
    line = WindowsEvents.convert(payload.to_json)
    refute_nil line
    assert_equal '192.0.2.42', fields(line)[0]
    assert_equal 'security', fields(line)[2]
  end

  # ---- output contract ---------------------------------------------------

  def test_every_converted_line_has_the_five_fields_stage_event_requires
    # stage_event returns early on fewer than 5 whitespace-separated tokens, so
    # a converted line that is too short is silently dropped by the importer.
    Dir[File.join(FIXTURE_DIR, '*')].sort.each do |path|
      line = WindowsEvents.convert(File.read(path))
      next if line.nil?
      assert_operator line.chomp.split(/ +/).size, :>=, 5,
                      "#{File.basename(path)} produced too few fields: #{line}"
    end
  end

  def test_converted_line_survives_stage_event_sanitizer_field_splitting
    # stage_event splits a sanitized copy (downcased, every character outside
    # [a-zA-Z0-9 \-_:@*/.] turned into a space) to find its fields. The host,
    # timestamp and service tokens must still be single tokens after that, or
    # the Service lookup lands on the wrong word.
    line = WindowsEvents.convert(fixture('security_4625.json'))
    sanitized = line.downcase.gsub(/([^a-zA-Z0-9 \-_:@\*\/.])/, ' ')
    parts = sanitized.split(/\s+/)
    assert_equal 'dc01.corp.example.com', parts[0]
    assert_equal '2024-03-02t09:15:04.928z', parts[1]
    assert_equal 'microsoft-windows-security-auditing', parts[2]
  end

  def test_key_value_pairs_keep_both_halves_searchable
    # Search is prefix matching over words.text. `eventid=4688` sanitizes to
    # two indexed words, eventid and 4688; `eventid:4688` would index as one
    # word that `4688` can never match.
    line = WindowsEvents.convert(fixture('security_4688.json'))
    words = line.downcase.gsub(/([^a-zA-Z0-9 \-_:@\*\/.])/, ' ').split(/\s+/)
    assert_includes words, 'eventid'
    assert_includes words, '4688'
  end

  def test_no_converted_line_contains_a_newline_or_tab
    Dir[File.join(FIXTURE_DIR, '*')].sort.each do |path|
      line = WindowsEvents.convert(File.read(path))
      next if line.nil?
      refute_match(/[\n\r\t]/, line.chomp, "#{File.basename(path)} produced a multi-line record")
    end
  end

  def test_unusable_records_convert_to_nil_rather_than_raising
    assert_nil WindowsEvents.convert('')
    assert_nil WindowsEvents.convert(fixture('empty.json'))
    assert_nil WindowsEvents.convert(fixture('malformed.json'))
    assert_nil WindowsEvents.convert(fixture('no_timestamp.json'))
    assert_nil WindowsEvents.convert('{"System":{"EventID":1},"OpenWEC":{}}')
    assert_nil WindowsEvents.convert('<NotAnEvent/>')
  end

  def test_long_rendered_message_is_truncated
    payload = {
      'System' => { 'EventID' => 4688, 'Channel' => 'Security', 'Computer' => 'h.local',
                    'TimeCreated' => '2024-01-01T00:00:00Z', 'Provider' => { 'Name' => 'P' } },
      'RenderingInfo' => { 'Message' => 'x' * 20_000 }
    }
    line = WindowsEvents.convert(payload.to_json)
    assert_operator line.length, :<, 25_000
    assert_includes line, '...'
  end

  def test_oversized_value_is_capped
    payload = {
      'System' => { 'EventID' => 4688, 'Channel' => 'Security', 'Computer' => 'h.local',
                    'TimeCreated' => '2024-01-01T00:00:00Z', 'Provider' => { 'Name' => 'P' } },
      'EventData' => { 'Blob' => 'y' * 50_000 }
    }
    line = WindowsEvents.convert(payload.to_json)
    value = line[/data_blob=(\S+)/, 1]
    assert_equal WindowsEvents::MAX_VALUE_CHARS + 3, value.length
  end

  # The XML arrives over the network from a Windows host, so it is
  # attacker-controlled. Nokogiri is configured with `nonet`; this pins that the
  # configuration is still there, since dropping it would not fail any other test.
  def test_raw_xml_does_not_expand_external_entities
    payload = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE Event [ <!ENTITY xxe SYSTEM "file:///etc/hostname"> ]>
      <Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
        <System>
          <Provider Name="Microsoft-Windows-Security-Auditing"/>
          <EventID>4720</EventID>
          <TimeCreated SystemTime="2024-03-02T11:22:33.123Z"/>
          <EventRecordID>30211</EventRecordID>
          <Channel>Security</Channel>
          <Computer>dc01.corp.example.com</Computer>
        </System>
        <EventData><Data Name="TargetUserName">&xxe;</Data></EventData>
      </Event>
    XML

    line = WindowsEvents.convert(payload)
    refute_nil line
    refute_includes line, 'root', 'an external entity was expanded into the stored record'
    refute_match(/data_targetusername=\S/, line,
                 'the entity reference should resolve to nothing, not file contents')
  end

end
