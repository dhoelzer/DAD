require 'windows_events'
require 'windows_forward'
require 'nokogiri'

# Polls one Windows host over WinRM and turns what it reads into staging records.
#
# This is the pull path: DAD connects out to the host and asks for records, using
# wevtutil on the remote side. It replaces the OpenWEC dependency, and unlike the
# push path it puts the cadence under DAD's control -- see WindowsTarget for how
# the interval is chosen.
#
# The transport is behind a seam (#run_command) rather than called inline. Not
# for mockery: there is no Windows host in CI, so the parsing, delta-query and
# queueing logic -- the parts that can actually be wrong -- has to be testable
# without one. The WinRM call itself is exercised by the smoke test only.
module WindowsPoll
  # Hard cap on records read per channel per poll. A host whose log has run away
  # should be polled again sooner rather than pinning this cycle for minutes; the
  # remainder comes in on the next poll, because the delta boundary advances only
  # past what was actually read.
  MAX_RECORDS_PER_CHANNEL = 5_000

  Result = Struct.new(:event_count, :status, :detail, keyword_init: true)

  class << self
    # Polls one target: reads each configured channel, converts, and enqueues.
    #
    # Returns a Result; never raises for a host-level failure. A host that is
    # down, firewalled, or has bad credentials is a normal condition in a fleet
    # of hundreds, and an exception here would abort the cycle and skip the
    # remaining targets.
    def poll(target, writer: nil, transport: nil)
      transport ||= Transport.new(target)
      writer ||= default_writer
      boundary = target.last_polled_at

      total = 0
      problems = []

      target.log_list.each do |channel|
        begin
          xml = transport.read_channel(channel, boundary)
          total += enqueue(xml, writer)
        rescue StandardError => e
          # One bad channel must not lose the others: a host where Security is
          # access-denied still yields its Application and System records. The
          # message is kept because "RuntimeError" tells an operator nothing --
          # wevtutil's own text is what names the cause.
          problems << "#{channel}: #{e.message}"
        end
      end

      writer.flush
      status = problems.empty? ? 'ok' : "partial: #{problems.join('; ')}"
      Result.new(event_count: total, status: status, detail: problems.join('; '))
    end

    # Converts a wevtutil <Events> document into staging lines and queues them.
    # Returns the number accepted.
    def enqueue(xml, writer)
      return 0 if xml.nil? || xml.strip.empty?

      # Parsed with the same hardening WindowsEvents applies: this XML comes from
      # a remote host, and nonet alone still resolves file:// entities.
      doc = Nokogiri::XML(xml) { |cfg| cfg.nonet.nodtdload }
      count = 0
      # wevtutil emits one <Event> per record inside an <Events> envelope; the
      # converter takes a single record, so the envelope is split here rather
      # than teaching the converter about a container it never sees from OpenWEC.
      doc.remove_namespaces!.css('Event').each do |node|
        line = WindowsEvents.convert(node.to_xml)
        next if line.nil?
        writer << line
        count += 1
      end
      count
    end

    def default_writer
      WindowsForward::Writer.new(
        ENV.fetch('WINDOWS_STAGING', 'Logs/WindowsStaging'),
        ENV.fetch('WINDOWS_QUEUE', 'Logs/LogsToProcess'))
    end

    # The XPath delta query.
    #
    # wevtutil has no cursor, so the boundary is time-based: records whose
    # TimeCreated falls within the last +window_ms+ milliseconds. Without it every
    # poll would re-read the whole channel and re-ingest the entire history as
    # duplicate events -- there is no dedup anywhere in the ingest path.
    #
    # The window is measured from the last poll, not from the epoch, and it is
    # widened by OVERLAP_SECS because a record's TimeCreated is when the event
    # occurred, not when it reached the channel: a service can log a timestamp
    # and have the write land seconds later. An exact boundary would drop those.
    #
    # The cost is that records inside the overlap can be ingested twice. That is
    # the deliberate trade: a duplicate row is visible and merely inflates a
    # count, whereas a missed record is invisible and silently under-reports.
    OVERLAP_SECS = 60

    def delta_query(since, limit: MAX_RECORDS_PER_CHANNEL)
      window = since.nil? ? FIRST_POLL_WINDOW_MS
                          : ((Time.now - since) * 1000).to_i + (OVERLAP_SECS * 1000)
      window = FIRST_POLL_WINDOW_MS if window < 0
      "TimeCreated[timediff(@SystemTime) <= #{window}]"
    end

    # With no previous poll, read the last 24h rather than the whole channel.
    # Bootstrapping a full history would take minutes per channel and flood the
    # queue on first contact with a new host.
    FIRST_POLL_WINDOW_MS = 86_400_000
  end

  # The WinRM side, isolated so the rest of the module runs without a host.
  class Transport
    def initialize(target)
      @target = target
    end

    def read_channel(channel, since)
      require 'winrm'
      out = connection.shell(:cmd) do |shell|
        shell.run_command(wevtutil_command(channel, since))
      end
      # A non-zero exit is a real failure, not an empty result: wevtutil exits 3
      # for an unknown channel and 5 for access denied, and reporting those as
      # "no events" would make a misconfigured or permission-locked channel look
      # quiet.
      raise "wevtutil exit #{out.exitcode}: #{out.stderr.to_s.strip}" unless out.exitcode.to_i.zero?
      out.stdout
    end

    # Channel names reach here only after WindowsTarget's LOG_NAME validation,
    # which is what keeps this command line safe to build by concatenation.
    #
    # /rd:true returns newest-first, so the cap keeps the most recent records
    # when a channel exceeds MAX_RECORDS_PER_CHANNEL rather than the oldest.
    def wevtutil_command(channel, since)
      query = WindowsPoll.delta_query(since)
      "wevtutil qe #{channel} /q:\"#{query}\" /e:xml /c:#{WindowsPoll::MAX_RECORDS_PER_CHANNEL} /rd:true"
    end

    def connection
      @connection ||= begin
        require 'winrm'
        WinRM::Connection.new(
          endpoint: "https://#{@target.address}:5986/wsman",
          user: @target.username,
          password: @target.password,
          # TLS by default. WinRM without it sends the NTLM exchange and every
          # record in the clear; 5986 is the encrypted listener.
          transport: :ssl,
          # The remote certificate is verified against the system trust store.
          # WINDOWS_SSL_VERIFY=none is an explicit operator decision to trust an
          # internal CA, not a default.
          ssl_verify_peer: ENV.fetch('WINDOWS_SSL_VERIFY', 'peer') != 'none',
          # Basic auth over the encrypted channel. Negotiate would be preferable
          # but needs a Kerberos/NTLM context this service does not hold.
          operation_timeout: 60,
          read_timeout: 120)
      end
    end
  end
end
