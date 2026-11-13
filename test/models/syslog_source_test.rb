require 'test_helper'

# Covers SyslogSource: deciding which token in a sanitized syslog line names the
# logging application and which names the host.
#
# Written against the token stream the parser actually sees, not the raw line.
# EventIngestor#stage_event downcases and replaces every character outside
# [a-zA-Z0-9 \-_:@*\/.] with a space BEFORE splitting, so the brackets in
# "sshd[4242]:" are already spaces by the time tokens exist. Asserting against
# "sshd[4242]:" would test a string the parser never looks at.
class SyslogSourceTest < ActiveSupport::TestCase
  # "<ip> Jun 1 12:00:00 sshd[4242]: Accepted" -> offset 4 is the app name.
  NO_HOSTNAME = %w[10.0.0.9 jun 1 12:00:00 sshd 4242 : accepted publickey].freeze
  # The RFC 3164 form rsyslog forwards by default carries a hostname slot.
  WITH_HOSTNAME = %w[10.0.0.5 jun 1 12:00:00 web01 sshd 4242 : accepted publickey].freeze
  # The Docker log-driver frame: no hostname slot, tag is the container name.
  DOCKER_FRAME = %w[172.18.0.1 nov 13 15:14:49 dad-web 149784 : started get /users/logon].freeze

  # An app name may keep '/' (postfix/smtp) and '.' after sanitizing.
  test "app name with no hostname slot resolves at the service offset" do
    resolved = SyslogSource.resolve(NO_HOSTNAME, 4)
    assert_equal 'sshd', resolved[:service]
    assert_nil resolved[:host]
  end

  # This is the mis-parse: the parser used to take the token at the service
  # offset unconditionally, so the hostname became the Service and the real
  # daemon name was dropped from the row entirely.
  test "a hostname slot is not mistaken for the service" do
    resolved = SyslogSource.resolve(WITH_HOSTNAME, 4)
    assert_equal 'sshd', resolved[:service]
    assert_equal 'web01', resolved[:host]
  end

  test "the docker log-driver frame names the service from the tag" do
    resolved = SyslogSource.resolve(DOCKER_FRAME, 4)
    assert_equal 'dad-web', resolved[:service]
    assert_nil resolved[:host]
  end

  test "a slash in an app name survives sanitizing and is still found" do
    tokens = %w[10.0.0.7 jun 1 12:00:00 postfix/smtp 9012 : connect to x]
    resolved = SyslogSource.resolve(tokens, 4)
    assert_equal 'postfix/smtp', resolved[:service]
    assert_nil resolved[:host]
  end

  # "sshd: Accepted" sanitizes to a single "sshd:" token -- no brackets, so no
  # pid slot. There is nothing structural to key on; the caller's old behaviour
  # (take the token at the offset) has to stay reachable.
  test "falls back to the service offset when there is no pid slot" do
    tokens = %w[10.0.0.9 jun 1 12:00:00 sshd: accepted publickey]
    resolved = SyslogSource.resolve(tokens, 4)
    assert_equal 'sshd:', resolved[:service]
    assert_nil resolved[:host]
  end

  # A message word must not be promoted to a service just because it is
  # followed by digits and a colon somewhere later in the line.
  test "does not scan into the message for a pid-shaped pattern" do
    tokens = %w[10.0.0.9 jun 1 12:00:00 sshd session opened for user bob 42 : uid]
    resolved = SyslogSource.resolve(tokens, 4)
    assert_equal 'sshd', resolved[:service]
  end

  test "returns nil service when the offset is past the end of the line" do
    resolved = SyslogSource.resolve(%w[10.0.0.9 jun 1 12:00:00], 4)
    assert_nil resolved[:service]
  end

  # --- gateway detection ----------------------------------------------------
  #
  # The rewrite that names a container after its tag is only correct when the
  # source address carries no host information, i.e. when it is this container's
  # own bridge gateway. Getting that test wrong would rename remote hosts.

  test "parses the default-route gateway out of /proc/net/route text" do
    # Captured verbatim from the importer container. Gateway is little-endian
    # hex: 010012AC -> 172.18.0.1.
    route = <<~ROUTE
      Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
      eth0\t00000000\t010012AC\t0003\t0\t0\t0\t00000000\t0\t0\t0
      eth0\t000012AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0
    ROUTE
    assert_equal ['172.18.0.1'], SyslogSource.parse_gateways(route)
  end

  test "collects every default route and ignores network routes" do
    # Two default routes (eth0, eth1) plus a network route whose Gateway field
    # is a next hop that says nothing about where a packet entered.
    route = <<~ROUTE
      Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
      eth0\t00000000\t010012AC\t0003\t0\t0\t0\t00000000\t0\t0\t0
      eth0\t000012AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0
      eth1\t00000000\t010013AC\t0003\t0\t0\t100\t00000000\t0\t0\t0
      eth0\t000113AC\t010013AC\t0003\t0\t0\t0\t00FFFFFF\t0\t0\t0
    ROUTE
    assert_equal ['172.18.0.1', '172.19.0.1'], SyslogSource.parse_gateways(route)
  end

  test "an unreadable route table yields no gateways rather than an error" do
    assert_empty SyslogSource.parse_gateways(nil)
    assert_empty SyslogSource.parse_gateways("")
  end

  test "a gateway address is recognised as carrying no host identity" do
    SyslogSource.stub_container_context(true, ['172.18.0.1']) do
      assert SyslogSource.self_host?('172.18.0.1')
      refute SyslogSource.self_host?('10.0.0.5')
    end
  end

  # Outside a container the address is the real peer, so nothing may be renamed.
  test "no address is treated as a self host when not containerised" do
    SyslogSource.stub_container_context(false, ['172.18.0.1']) do
      refute SyslogSource.self_host?('172.18.0.1')
    end
  end

  # Escape hatch for the case where something real does send from the bridge
  # address -- the Docker host itself, or a VM behind the same bridge.
  test "DAD_SYSLOG_SELF_HOST=none disables the rewrite" do
    SyslogSource.stub_container_context(true, ['172.18.0.1']) do
      with_env('DAD_SYSLOG_SELF_HOST', 'none') do
        refute SyslogSource.self_host?('172.18.0.1')
      end
      with_env('DAD_SYSLOG_SELF_HOST', 'NONE') do
        refute SyslogSource.self_host?('172.18.0.1')
      end
      assert SyslogSource.self_host?('172.18.0.1')
    end
  end

  test "system_override returns nil when the address is not a self host" do
    SyslogSource.stub_container_context(true, ['172.18.0.1']) do
      resolved = { service: 'dad-web', host: nil }
      assert_equal 'dad-web', SyslogSource.system_override('172.18.0.1', resolved)
      assert_nil SyslogSource.system_override('10.0.0.5', resolved)
    end
  end

  # A hostname slot beats the tag: it is host information that was stated
  # rather than inferred.
  test "system_override prefers an explicit hostname slot over the tag" do
    SyslogSource.stub_container_context(true, ['172.18.0.1']) do
      resolved = { service: 'postfix/smtp', host: 'relay01' }
      assert_equal 'relay01', SyslogSource.system_override('172.18.0.1', resolved)
    end
  end

  test "system_override returns nil when there is nothing to use" do
    SyslogSource.stub_container_context(true, ['172.18.0.1']) do
      assert_nil SyslogSource.system_override('172.18.0.1', { service: nil, host: nil })
    end
  end

  private

  def with_env(name, value)
    before = ENV[name]
    ENV[name] = value
    yield
  ensure
    ENV[name] = before
  end
end
