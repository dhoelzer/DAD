require 'test_helper'

# End-to-end: what System and Service a stored event actually lands on.
#
# The unit tests for SyslogSource cover the token arithmetic. This covers the
# part that can only be checked through EventIngestor -- that the decision is
# applied to the row, and that the container rewrite is gated on the source
# address really being this host's gateway.
#
# Container detection is stubbed because the test suite runs both inside the
# compose test container (where /proc/net/route shows a bridge) and on a
# developer's bare host (where it does not), and the assertions must mean the
# same thing in both places.
class SyslogIngestIdentityTest < ActionDispatch::IntegrationTest
  GATEWAY = '172.18.0.1'.freeze

  def setup
    EventIngestor.resetCaches
    EventIngestor.bulk_insert_size = 1
    # System/Service memoize rows in class variables that outlive the per-test
    # transaction rollback, so a later test would be handed an id whose row no
    # longer exists.
    System.class_variable_set(:@@cached_stuff, Hash.new)
    Service.class_variable_set(:@@cached_stuff, Hash.new)
  end

  def teardown
    SyslogSource.instance_variable_set(:@containerized, nil)
    SyslogSource.instance_variable_set(:@gateway_addresses, nil)
  end

  # Returns [system_identity, service_name] for the row +line+ produced.
  def ingest(line)
    EventIngestor.storeEvent(line)
    EventIngestor.performPendingInserts
    event = Event.order(:id).last
    return [nil, nil] if event.nil?
    [System.find(event.system_id).address, Service.find(event.service_id).name]
  end

  def ingest_in_container(line)
    SyslogSource.stub_container_context(true, [GATEWAY]) { ingest(line) }
  end

  # The bug. Every container arrives carrying the bridge gateway as its source
  # address, so the whole stack used to collapse into one System row labelled
  # "(172.18.0.1)" while each container name was filed as a Service.
  test "a container log becomes its own system, named by its tag" do
    system, service = ingest_in_container(
      '172.18.0.1 Nov 13 15:14:49 dad-web[149784]: Started GET /users/logon')
    assert_equal 'dad-web', system
    assert_equal 'dad-web', service
  end

  # The pid in dad-web[149784] is dockerd's, identical for every container in
  # the stack, so it must not reach either column.
  test "the pid never becomes part of the system or service name" do
    system, service = ingest_in_container(
      '172.18.0.1 Nov 13 15:14:49 dad-db[149784]: database system is ready')
    assert_equal 'dad-db', system
    assert_equal 'dad-db', service
    refute_match(/\d/, system)
  end

  # Two containers on one gateway must not share a System row -- that was the
  # whole complaint.
  test "containers on the same gateway get separate system rows" do
    web, dbs = ingest_in_container('172.18.0.1 Nov 13 15:14:49 dad-web[1]: one two three'),
               ingest_in_container('172.18.0.1 Nov 13 15:14:50 dad-db[1]: four five six')
    assert_equal 'dad-web', web[0]
    assert_equal 'dad-db', dbs[0]
    refute_equal web[0], dbs[0]
  end

  # The gate. A remote host's address is its own identity; rewriting it because
  # it happens to match a gateway would mislabel real hosts.
  test "a remote host keeps its address as the system" do
    system, service = SyslogSource.stub_container_context(true, [GATEWAY]) do
      ingest('10.0.0.9 Jun 1 12:00:00 sshd[4242]: accepted publickey for alice')
    end
    assert_equal '10.0.0.9', system
    assert_equal 'sshd', service
  end

  # Same line, same gateway address, but the importer is not containerized --
  # e.g. the systemd deployment on the Docker host. Nothing may be renamed.
  test "no rewrite happens when the importer is not containerized" do
    system, service = SyslogSource.stub_container_context(false, [GATEWAY]) do
      ingest('172.18.0.1 Nov 13 15:14:49 dad-web[149784]: started get /users/logon')
    end
    assert_equal '172.18.0.1', system
    assert_equal 'dad-web', service
  end

  # RFC 3164 as rsyslog forwards it by default carries a hostname slot. The old
  # parser took it for the Service (and its sanitizer strips digits, so
  # "web01" became "web") and dropped the daemon name entirely.
  test "an rfc3164 hostname slot is not filed as the service" do
    system, service = ingest(
      '10.0.0.5 Jun 1 12:00:00 web01 sshd[4242]: accepted publickey for bob')
    assert_equal '10.0.0.5', system
    assert_equal 'sshd', service
  end

  # A hostname slot plus a gateway address: the hostname is better host
  # information than either the gateway or the tag.
  test "an explicit hostname slot wins over the tag when rewriting" do
    system, service = ingest_in_container(
      '172.18.0.1 Jun 1 12:00:00 relay01 postfix/smtp[9012]: connect to mx.example.com')
    assert_equal 'relay01', system
    assert_equal 'postfix/smtp', service
  end

  # The service name sanitizer strips digits, so a tag that is all digits
  # leaves nothing. Storing that would create a Service no view can label.
  test "a line whose service sanitizes to nothing is not stored" do
    before = Event.count
    SyslogSource.stub_container_context(true, [GATEWAY]) do
      EventIngestor.storeEvent('172.18.0.1 Nov 13 15:14:49 149784[149784]: no name here')
      EventIngestor.performPendingInserts
    end
    assert_equal before, Event.count
  end
end
