# Converts one OpenWEC output record into the staging line EventIngestor expects.
#
# OpenWEC (https://github.com/cea-sec/openwec) collects Windows event logs over
# MS-WSMV and writes them as JSON or raw XML. DAD's ingest side reads lines of
# the form
#
#   <host> <timestamp> <service> <words...>
#
# EventIngestor.stage_event takes field 0 as the System address, parses a
# timestamp out of field 1.., and takes the token immediately after the
# timestamp as the Service name. It already accepts RFC 3339 (parse_timestamp
# format 1), so a Windows event maps onto that shape with no change to the
# importer at all. This file is the whole integration.
#
# Why a converter rather than a second ingest pipeline: the importer's word
# indexing, batch chunking, checkpointing, per-line rescue and partition-aware
# id allocation are all engine-specific and already tested. A parallel pipeline
# would duplicate every one of those and then drift.
#
# Four OpenWEC output formats are handled, because which one you pick is a
# deployment choice, not a code one:
#
#   Json        {"System": {...}, "EventData": {...}, "OpenWEC": {...}}
#   Nxlog       flattened: {"SourceName":..., "Hostname":..., "EventID":...}
#   Raw / JsonRaw  the untouched <Event> XML, optionally wrapped as
#                  {"meta": {...}, "data": "<Event>...</Event>"}
#
# What the line eventually becomes constrains how it is built. stage_event keeps
# `hunks` verbatim for display and export, but splits a *sanitized* copy --
# downcased, every character outside [a-zA-Z0-9 \-_:@*/.] replaced by a space --
# to pick its fields and to build the word index. Two consequences this file
# relies on:
#
#   * `=` is not in that set, so `eventid=4688` reads as two indexed words,
#     `eventid` and `4688`, while still displaying as `eventid=4688`. Emitting
#     key=value therefore keeps both halves searchable, which `eventid:4688`
#     would not: search is prefix matching, so `4688` could never match inside
#     `eventid:4688`.
#   * `+` is also replaced by a space, which would split an RFC 3339 `+HH:MM`
#     offset in two and shift the Service field off its offset. Timestamps are
#     normalized to a literal `Z` here so that cannot happen.
module WindowsEvents
  # Longest value emitted for a single field. A rendered Windows message can run
  # to several kilobytes; past this it is truncated with an ellipsis so one
  # event cannot dominate the word index or the hunks column.
  MAX_VALUE_CHARS = 4000

  # OpenWEC's Nxlog format flattens System, EventData and RenderingInfo into one
  # object. These are the flattened System / RenderingInfo names (upstream
  # server/src/formats/nxlog.rs); anything else in the object came from
  # EventData. They differ from the Json format: Hostname not Computer,
  # EventTime not TimeCreated, SourceName not Provider.Name, Category not Task.
  NXLOG_SYSTEM_FIELDS = %w[
    SourceName ProviderGuid EventID Version Task OpcodeValue Keywords EventTime
    RecordNumber Channel Hostname UserID EventType Severity SeverityValue
    EventReceivedTime Category Opcode Message
  ].freeze

  # Converts one OpenWEC record (no trailing newline) to one staging line.
  # Returns nil when the record carries nothing ingestible; callers log and skip.
  def self.convert(line)
    payload = line.to_s.strip
    return nil if payload.empty?

    parts = parse(payload)
    return nil if parts.nil?

    render(parts)
  end

  # Picks a parser from the payload's shape rather than from configuration: the
  # format is set per OpenWEC subscription, so one input file can legitimately
  # mix them during a migration.
  def self.parse(payload)
    case detect(payload)
    when :json     then from_json(payload)
    when :nxlog    then from_nxlog(payload)
    when :raw_json then from_raw_json(payload)
    when :xml      then from_xml(payload)
    end
  end

  def self.detect(payload)
    case payload[0]
    when '{'
      doc = json_document(payload)
      return nil if doc.nil?
      if doc['data'].is_a?(String) && doc['data'].lstrip.start_with?('<')
        :raw_json
      elsif doc.key?('System')
        :json
      elsif (doc.keys & %w[EventID Hostname SourceName]).any?
        :nxlog
      end
    when '<'
      :xml
    end
  end

  def self.json_document(payload)
    require 'json'
    JSON.parse(payload)
  rescue JSON::ParserError
    nil
  end

  # ---- Json format -------------------------------------------------------

  def self.from_json(payload)
    doc = json_document(payload)
    return nil unless doc.is_a?(Hash)

    system = doc['System'] || {}
    fields = {}

    add(fields, 'eventid', system['EventID'])
    add(fields, 'channel', system['Channel'])
    add(fields, 'level', system['Level'])
    add(fields, 'record', system['EventRecordID'])
    add(fields, 'keywords', system['Keywords'])
    add(fields, 'task', system['Task'])
    add(fields, 'opcode', system['Opcode'])
    add(fields, 'userid', system['UserID'])
    add(fields, 'provider', system.dig('Provider', 'Name'))
    add(fields, 'activityid', system.dig('Correlation', 'ActivityID'))
    add(fields, 'processid', system.dig('Execution', 'ProcessID'))
    (doc['EventData'] || {}).each { |k, v| add(fields, "data_#{k.downcase}", v) }
    add(fields, 'binary', doc['BinaryEventData'])
    add(fields, 'message', doc.dig('RenderingInfo', 'Message'))

    {
      # A WEC client IP is the address of the machine the event came from, which
      # is what DAD keys a System on, so it is a usable stand-in when the event
      # carries no Computer name.
      host: system['Computer'] || doc.dig('OpenWEC', 'IpAddress'),
      timestamp: system['TimeCreated'] || doc.dig('OpenWEC', 'TimeReceived'),
      service: system.dig('Provider', 'Name') || system['Channel'],
      openwec: doc['OpenWEC'] || {},
      fields: fields
    }
  end

  # ---- Nxlog format ------------------------------------------------------

  def self.from_nxlog(payload)
    doc = json_document(payload)
    return nil unless doc.is_a?(Hash)

    fields = {}
    doc.each do |key, value|
      # OpenWEC's envelope is metadata about the delivery, not event content;
      # its interesting members are folded in by render via :openwec.
      next if key == 'OpenWEC'
      # Hostname and EventTime become the structural host/timestamp tokens, so
      # they are not repeated in the body.
      next if %w[Hostname EventTime].include?(key)
      if NXLOG_SYSTEM_FIELDS.include?(key)
        add(fields, key.downcase, value)
      else
        add(fields, "data_#{key.downcase}", value)
      end
    end

    {
      host: doc['Hostname'],
      timestamp: doc['EventTime'] || doc['EventReceivedTime'],
      service: doc['SourceName'] || doc['Channel'],
      openwec: doc['OpenWEC'] || {},
      fields: fields
    }
  end

  # ---- Raw / JsonRaw format ----------------------------------------------

  def self.from_raw_json(payload)
    doc = json_document(payload)
    return nil unless doc.is_a?(Hash)

    xml = doc['data']
    return nil unless xml.is_a?(String)

    parts = from_xml(xml)
    return nil if parts.nil?

    # JsonRaw carries the client IP and receive time in meta, which is where a
    # host has to come from when the XML's Computer element is absent.
    meta = doc['meta'] || {}
    parts[:host] ||= meta['IpAddress']
    parts[:timestamp] ||= meta['TimeReceived']
    parts[:openwec] = meta
    parts
  end

  # ---- Raw XML -----------------------------------------------------------
  #
  # Elements are matched by local name rather than by XPath with a namespace
  # prefix. event.xsd's namespace URI has been stable since Vista, but Windows
  # emits it as the *default* namespace, so a bare `./System` matches nothing,
  # and a hard-coded prefix fails on the namespace-less XML that `wevtutil` and
  # hand-written fixtures produce. Matching the local name handles both, and
  # handles a `p:System` prefix for free.

  def self.from_xml(payload)
    require 'nokogiri'
    # This XML is attacker-controlled: it arrives over the network from a
    # Windows host. nonet blocks fetching external entities over the network,
    # and nodtdload blocks the DTD subset that declares them at all -- which
    # also covers file:// and other non-network schemes nonet leaves alone. A
    # real Windows event carries no DTD, so this costs nothing.
    doc = Nokogiri::XML(payload) { |cfg| cfg.nonet.nodtdload }
    root = doc.root
    return nil if root.nil? || local_name(root) != 'Event'

    system = child(root, 'System')
    return nil if system.nil?

    provider = child(system, 'Provider')
    provider_name = provider && provider['Name']
    channel = text_of(system, 'Channel')
    time_created = child(system, 'TimeCreated')

    fields = {}
    add(fields, 'eventid', text_of(system, 'EventID'))
    add(fields, 'channel', channel)
    add(fields, 'level', text_of(system, 'Level'))
    add(fields, 'record', text_of(system, 'EventRecordID'))
    add(fields, 'keywords', text_of(system, 'Keywords'))
    add(fields, 'task', text_of(system, 'Task'))
    add(fields, 'opcode', text_of(system, 'Opcode'))
    add(fields, 'provider', provider_name)
    # <Security UserID="..."/> carries the actor as an attribute, not text.
    add(fields, 'userid', child(system, 'Security')&.[]('UserID'))

    event_data = child(root, 'EventData')
    children(event_data).each_with_index do |node, i|
      key = node['Name'] || "item#{i + 1}"
      add(fields, "data_#{key.downcase}", node.text)
    end
    rendering = child(root, 'RenderingInfo')
    add(fields, 'message', text_of(rendering, 'Message'))

    {
      host: presence(text_of(system, 'Computer')),
      timestamp: presence(time_created && (time_created['SystemTime'] || time_created.text)),
      service: presence(provider_name || channel),
      openwec: {},
      fields: fields
    }
  end

  def self.local_name(node)
    node.name.split(':').last
  end

  def self.children(node)
    return [] if node.nil?
    node.elements
  end

  def self.child(node, name)
    children(node).find { |e| local_name(e) == name }
  end

  def self.text_of(node, name)
    return nil if node.nil?
    found = child(node, name)
    found && found.text
  end

  # ---- shared ------------------------------------------------------------

  # Turns the extracted parts into the final line, or nil when a structural
  # token is missing. A record with no usable host or timestamp is not a
  # partial event -- it is unplaceable -- so it is dropped rather than guessed.
  def self.render(parts)
    host = sanitize_token(parts[:host])
    service = sanitize_token(parts[:service])
    stamp = normalize_time(parts[:timestamp])
    return nil if host.nil? || service.nil? || stamp.nil?

    openwec = parts[:openwec] || {}
    fields = parts[:fields]
    add(fields, 'client', openwec['Principal'] || openwec['Client'])
    add(fields, 'subscription', openwec.dig('Subscription', 'Name'))
    add(fields, 'node', openwec['Node'])

    body = fields.map { |k, v| "#{k}=#{v}" }.join(' ')
    return nil if body.empty?

    "#{host} #{stamp} #{service} #{body}\n"
  end

  def self.presence(value)
    text = value.to_s.strip
    text.empty? ? nil : text
  end

  # Adds a key/value pair, dropping empty values and flattening anything that
  # would break the one-record-per-line contract.
  #
  # Keys are downcased by every caller; values keep their case. The word index
  # downcases regardless, so this only changes how `hunks` reads in the UI and in
  # exports -- but it has to be uniform, or the same event arriving as Json
  # versus Nxlog would display under two different key spellings.
  def self.add(fields, key, value)
    return if value.nil?
    text = value.to_s.gsub(/[\r\n\t]+/, ' ').squeeze(' ').strip
    return if text.empty?
    text = "#{text[0, MAX_VALUE_CHARS]}..." if text.length > MAX_VALUE_CHARS
    fields[key] = text
  end

  # A value that will be read back as one whitespace-separated field.
  # stage_event splits on runs of whitespace, so a token must not contain one.
  #
  # Spaces become hyphens rather than disappearing: 'Service Control Manager'
  # reads as service-control-manager instead of servicecontrolmanager, and '-'
  # is one of the characters stage_event's sanitizer keeps, so the token still
  # survives intact and indexes as a single word.
  def self.sanitize_token(value)
    return nil if value.nil?
    token = value.to_s.downcase.gsub(/\s+/, '-')
    token = token.gsub(/\A-+|-+\z/, '')
    token.empty? ? nil : token
  end

  # RFC 3339 with a literal Z and millisecond precision.
  #
  # Windows emits 7-9 fractional digits ("2022-12-14T16:06:51.064360500Z") and
  # OpenWEC's own timestamps emit a UTC offset. Both parse, but only the Z form
  # survives stage_event's sanitizer intact: '+' becomes a space, which would
  # split the timestamp across two tokens.
  def self.normalize_time(value)
    return nil if value.nil?
    require 'date'
    DateTime.parse(value.to_s).new_offset(0).strftime('%Y-%m-%dT%H:%M:%S.%LZ')
  rescue ArgumentError
    nil
  end
end
