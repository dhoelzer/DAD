# Deciding which token in a syslog line names the logging *application* and which
# names the *host* it came from.
#
# EventIngestor used to assume the token immediately after the timestamp was the
# application, and the source address was the host. That holds for exactly one
# frame shape and silently produces nonsense for the two others that matter here:
#
#   1. The Docker log driver. Compose tags each service, and the driver emits
#      `dad-web[149784]: msg` with the RFC 3164 hostname slot left out. The
#      collector prepends the address the packet came from, which for every
#      container is the bridge gateway, so all of them collapse into one System
#      row and the container name -- the only host identity in the line -- is
#      filed as a Service.
#
#   2. RFC 3164 as rsyslog forwards it by default, which *does* carry a hostname
#      slot: `10.0.0.5 Jun 1 12:00:00 web01 sshd[4242]: ...`. The old code took
#      `web01` as the Service (and its sanitizer strips digits, so the row said
#      `web`) and dropped `sshd` entirely.
#
# Both are the same question, so it gets one answer here: find the application
# slot structurally rather than positionally, and treat a token that turns out to
# be a host as host information.
#
# Everything here works on the token array EventIngestor has already sanitized --
# downcased, with every character outside [a-zA-Z0-9 \-_:@*\/.] replaced by a
# space. That matters: the brackets in `sshd[4242]:` are *spaces* by the time
# tokens exist, so the application slot is recognised as `name digits :`, not as
# `name[pid]:`.
module SyslogSource
  # How far past the expected application slot to look for a hostname slot. One
  # is the RFC 3164 shape; more than that means the line is not shaped like
  # syslog at all, and scanning further would start matching message words.
  HOST_SLOT_WINDOW = 1

  class << self
    # Test seams. Container detection reads the host's /proc, which a test cannot
    # control, and the results are memoised for the process lifetime because this
    # runs on every ingested line.
    attr_writer :containerized, :gateway_addresses

    def containerized
      return @containerized unless @containerized.nil?
      @containerized = detect_containerized
    end

    # Gateways of this host's default routes, as dotted-quad strings. Memoised:
    # a container's route table does not change while it runs, and reading
    # /proc/net/route per ingested line would be absurd.
    def gateway_addresses
      return @gateway_addresses unless @gateway_addresses.nil?
      @gateway_addresses = parse_gateways(read_proc_file('/proc/net/route'))
    end

    # Runs the block with container detection forced, then restores memoisation.
    def stub_container_context(in_container, gateways)
      before = [defined?(@containerized) ? @containerized : nil,
                defined?(@gateway_addresses) ? @gateway_addresses : nil]
      @containerized = in_container
      @gateway_addresses = gateways
      yield
    ensure
      @containerized, @gateway_addresses = before
    end
  end

  # Splits the application out of the token stream.
  #
  # +offset+ is where the application is expected -- the token after the
  # timestamp. Returns {service:, host:}; :host is set only when the token at
  # +offset+ turned out to be a hostname rather than the application, in which
  # case :service is the token after it.
  #
  # :service is returned raw and unsanitized for the Service lookup; the caller
  # keeps its own Service name sanitizer so that behaviour does not move here.
  def self.resolve(tokens, offset)
    return { service: nil, host: nil } if tokens.nil? || tokens.empty?
    app = app_index(tokens, offset)
    return { service: nil, host: nil } if app.nil?
    { service: tokens[app], host: app > offset ? tokens[offset] : nil }
  end

  # Index of the token naming the logging application.
  #
  # The marker is structural, not positional: an application in syslog is
  # followed by its pid and then a colon, which after sanitizing is
  # `name` `digits` `:`. A hostname slot has no pid after it, so the token that
  # owns the pid slot is the application whichever of the two slots is present.
  #
  # When nothing near the offset owns a pid slot -- "sshd: Accepted", which
  # sanitizes to a single `sshd:` token with no pid -- there is nothing
  # structural to key on and the expected offset is used, which is what the
  # parser has always done.
  def self.app_index(tokens, offset)
    return nil if offset >= tokens.size
    (0..HOST_SLOT_WINDOW).each do |skip|
      index = offset + skip
      return index if owns_pid_slot?(tokens, index)
    end
    offset
  end

  def self.owns_pid_slot?(tokens, index)
    return false if index >= tokens.size
    return false if index + 1 >= tokens.size
    tokens[index + 1] =~ /\A\d+\z/ && tokens[index + 2] == ':'
  end

  # A name to use instead of the source address as the System identity, or nil
  # to keep the address.
  #
  # Only ever returned when the source address carries no host information of
  # its own -- see self_host?. Prefers an explicit hostname slot; failing that,
  # the application token, which under the Docker log driver is the container
  # tag and is the only host identity the line contains.
  def self.system_override(address, resolved)
    return nil unless self_host?(address)
    resolved[:host] || resolved[:service]
  end

  # True when +address+ is one of this host's own default-route gateways, i.e.
  # the packet was relayed by the local bridge rather than sent by a host that
  # can be identified by its address.
  #
  # Gated on containerization deliberately. Without it, a systemd deployment on
  # a plain network would rewrite any syslog that happened to arrive from the
  # LAN router -- and routers do send syslog -- into a System named after
  # whatever tag the router used. Requiring a container restricts the rewrite to
  # the deployment where the gateway really is a Docker bridge. The cost: a
  # non-containerized importer on the Docker host keeps the old behaviour.
  #
  # DAD_SYSLOG_SELF_HOST=none turns the rewrite off entirely, for the case where
  # something real does send from the bridge address -- the Docker host itself,
  # or a VM behind the same bridge.
  def self.self_host?(address)
    return false if address.nil? || address.empty?
    return false if ENV['DAD_SYSLOG_SELF_HOST'].to_s.casecmp('none').zero?
    return false unless containerized
    gateway_addresses.include?(address)
  end

  # Default-route gateways from /proc/net/route text.
  #
  # Only rows whose Destination is 00000000 (the default route) count; the rest
  # are network routes whose Gateway field is 00000000 or a next hop that says
  # nothing about where a syslog packet entered.
  #
  # Returns [] rather than raising on unreadable input: this runs during
  # ingestion, and a parse problem here must not stop events being stored.
  def self.parse_gateways(text)
    return [] if text.nil? || text.empty?
    rows = text.split("\n").drop(1)
    rows.filter_map do |row|
      columns = row.split
      next unless columns.size >= 3
      next unless columns[1] == '00000000'
      decode_route_hex(columns[2])
    end
  end

  # /proc/net/route prints addresses as 8 hex digits in *host* byte order, so on
  # the little-endian architectures this runs on, 010012AC is 172.18.0.1 read
  # backwards.
  def self.decode_route_hex(hex)
    return nil unless hex =~ /\A[0-9a-fA-F]{8}\z/
    groups = hex.scan(/../).reverse
    return nil unless groups.size == 4
    groups.map { |group| group.to_i(16) }.join('.')
  end

  def self.detect_containerized
    return true if File.exist?('/.dockerenv')
    return true if File.exist?('/run/.containerenv')
    # cgroup v1 leaves the runtime name in the path; cgroup v2 (what Docker 29
    # presents here) shows only "0::/", so this is the fallback, not the path.
    %w[/proc/1/cgroup /proc/self/cgroup].any? do |path|
      contents = read_proc_file(path)
      !contents.nil? && contents =~ /docker|containerd|kubepods|podman/
    end
  end

  def self.read_proc_file(path)
    File.read(path)
  rescue SystemCallError, IOError
    nil
  end
end
