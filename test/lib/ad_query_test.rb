require 'test_helper'
require_relative '../../lib/ad_query'

# AdQuery is the LDAP layer for the Active Directory import. There is no domain
# controller in CI, so these tests cover the parts that can actually be wrong:
# filter construction, escaping, workstation/server classification, and the
# address matching that decides whether a host is already a target.
#
# The search itself is exercised through an injected client, which is the same
# seam WindowsPoll::Transport uses -- the seam exists so the logic is testable,
# not so it can be mocked in place of real behaviour.
class AdQueryTest < ActiveSupport::TestCase
  # Stands in for LdapClient. Returns canned computer objects in the shape
  # net-ldap hands back (attribute names as the server sent them, values in
  # arrays), and records the filter it was asked to run.
  class FakeClient
    attr_reader :filter, :attributes

    def initialize(entries)
      @entries = entries
    end

    def search_computers(filter, attributes)
      @filter = filter
      @attributes = attributes
      @entries
    end
  end

  def entry(dns:, name: nil, os: nil, gid: nil, created: nil)
    e = { 'dnshostname' => [dns].compact, 'name' => [name || dns].compact }
    e['operatingsystem'] = [os] if os
    e['primarygroupid'] = [gid] if gid
    e['whencreated'] = [created] if created
    e
  end

  # ---- filter construction -------------------------------------------------

  test 'the workstation filter excludes Server and requires Windows' do
    filter = AdQuery.build_filter(host_filter: 'workstations')
    assert_equal '(&(objectClass=computer)(!(operatingSystem=*Server*))(operatingSystem=Windows*))',
                 filter
  end

  test 'the server filter matches Server anywhere in the OS string' do
    assert_equal '(&(objectClass=computer)(operatingSystem=*Server*))',
                 AdQuery.build_filter(host_filter: 'servers')
  end

  test 'all imposes no OS constraint' do
    assert_equal '(objectClass=computer)', AdQuery.build_filter(host_filter: 'all')
    assert_equal '(objectClass=computer)', AdQuery.build_filter(host_filter: '')
    assert_equal '(objectClass=computer)', AdQuery.build_filter
  end

  # An unknown filter string must not quietly degrade to "everything": the
  # operator asked for servers and would get the whole domain.
  test 'an unknown host filter raises rather than falling back to all' do
    assert_raises(ArgumentError) { AdQuery.build_filter(host_filter: 'everything') }
  end

  # ---- escaping ------------------------------------------------------------

  # `* ( ) \` are LDAP filter syntax. Unescaped, a value containing them changes
  # the structure of the query: `*)(objectClass=user` closes the real filter and
  # opens a new one, turning a computer lookup into something else.
  test 'filter metacharacters in a value are escaped, not interpolated' do
    filter = AdQuery.build_filter(name_contains: '*)(objectClass=user')
    assert_equal '(&(objectClass=computer)(name=\*\)\(objectClass=user*))', filter

    # Structural check. The escaped text still contains the characters
    # "objectClass=", so counting substrings proves nothing. What matters is that
    # every injected metacharacter carries a backslash and the group nesting is
    # still exactly the two conjuncts that were built.
    unescaped_open  = filter.scan(/(?<!\\)\(/).size
    unescaped_close = filter.scan(/(?<!\\)\)/).size
    assert_equal 3, unescaped_open, 'expected exactly the &, computer, and name groups'
    assert_equal unescaped_open, unescaped_close, 'paren nesting must stay balanced'
  end

  test 'a backslash in a value is escaped' do
    assert_includes AdQuery.build_filter(name_contains: 'a\\b'), '(name=a\\\\b*)'
  end

  # NUL is the LDAP protocol delimiter. RFC 4515 wants it as the hex pair \00.
  # Two Ruby traps sit on this line: '\00' is an octal escape (a NUL byte), and
  # a gsub *string* replacement re-reads \0 as a backreference to the match.
  # Both would put the delimiter back into the filter while looking escaped.
  test 'NUL is escaped to the hex pair, leaving no NUL byte in the filter' do
    escaped = AdQuery.escape_value("a#{0.chr}b")

    refute_includes escaped, 0.chr, 'a NUL byte in a filter is a protocol delimiter'
    assert_equal 'a\\00b', escaped
  end

  test 'escaping leaves ordinary values alone' do
    assert_equal 'web01', AdQuery.escape_value('web01')
    assert_equal 'SQL-01.corp.example.com', AdQuery.escape_value('SQL-01.corp.example.com')
  end

  # ---- classification ------------------------------------------------------

  # AD stores operatingSystem as free text. These are the strings it actually
  # emits; the point is that a non-Windows or unset OS is its own category
  # rather than a guess that failed.
  test 'classifies AD operatingSystem strings' do
    assert_equal :server,      AdQuery.classify('Microsoft Windows Server 2019 Standard')
    assert_equal :server,      AdQuery.classify('Windows Server 2022 Datacenter')
    assert_equal :workstation, AdQuery.classify('Microsoft Windows 10 Pro')
    assert_equal :workstation, AdQuery.classify('Microsoft Windows 11 Enterprise')
    assert_equal :workstation, AdQuery.classify('Windows 10 Pro for Workstations')
  end

  # A SKU naming both is a server.
  test 'Server wins when a string names both' do
    assert_equal :server, AdQuery.classify('Windows Server Standard for Workstations')
  end

  # Linux boxes joined to AD, appliances, and machines whose OS was never
  # recorded. Importing these as Windows hosts produces targets that can never
  # poll successfully.
  test 'non-Windows and unset operating systems classify as unknown' do
    assert_equal :unknown, AdQuery.classify('Ubuntu 22.04 LTS')
    assert_equal :unknown, AdQuery.classify('')
    assert_equal :unknown, AdQuery.classify(nil)
    assert_equal :unknown, AdQuery.classify('   ')
  end

  # ---- address matching ----------------------------------------------------

  # AD returns dNSHostName fully qualified; an operator adding a host by hand
  # types the short name. Treating those as different strings yields two targets
  # for one machine, which double-polls it and interleaves two offset states.
  test 'host aliases cover the FQDN and the short name, lowercased' do
    assert_equal ['web01.corp.example.com', 'web01'],
                 AdQuery.host_aliases('WEB01.Corp.Example.COM')
    assert_equal ['web01'], AdQuery.host_aliases('web01')
    assert_equal [], AdQuery.host_aliases('')
    assert_equal [], AdQuery.host_aliases(nil)
  end

  test 'already_present matches an existing target on either alias form' do
    existing = WindowsTarget.create!(
      address: 'matched01', name: 'short entry',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application')

    # FQDN from AD, short name in the database.
    assert_includes AdQuery.already_present(['matched01.corp.example.com']), 'matched01'
    # And the other way round.
    assert_includes AdQuery.already_present(['matched01']), 'matched01'
    # Case-insensitive: AD returns whatever case the machine registered.
    assert_includes AdQuery.already_present(['MATCHED01.CORP.EXAMPLE.COM']), 'matched01'

    refute_includes AdQuery.already_present(['notpresent.corp.example.com']), 'notpresent'
    assert_empty AdQuery.already_present([])
  ensure
    existing&.destroy
  end

  # ---- run -----------------------------------------------------------------

  test 'run returns usable entries, existing addresses, and an unnamed count' do
    client = FakeClient.new([
      entry(dns: 'web01.corp.example.com', os: 'Microsoft Windows 10 Pro'),
      entry(dns: 'sql01.corp.example.com', os: 'Microsoft Windows Server 2019 Standard'),
      entry(dns: nil, os: 'Microsoft Windows 10 Pro'),
    ])

    WindowsTarget.create!(address: 'web01', name: 'pre-existing short name',
                          polling_priority: PollingPriority.find_by(name: 'Priority 1'),
                          event_logs: 'Application')

    usable, present, unnamed = AdQuery.run(nil, host_filter: 'all', client: client)

    assert_equal %w[web01.corp.example.com sql01.corp.example.com], usable.map(&:address)
    assert_equal ['web01'], present
    assert_equal 1, unnamed
  end

  test 'entries with no dNSHostName are excluded from the usable list' do
    # A computer object that never registered a DNS name cannot be connected to
    # over WinRM, so it cannot become a target.
    client = FakeClient.new([entry(dns: nil, os: 'Microsoft Windows 10 Pro')])
    usable, _present, unnamed = AdQuery.run(nil, client: client)

    assert_empty usable
    assert_equal 1, unnamed
  end

  test 'addresses are lowercased so the same host cannot appear twice' do
    client = FakeClient.new([entry(dns: 'WEB01.Corp.Example.COM', os: 'Microsoft Windows 10 Pro')])
    usable, _present, _unnamed = AdQuery.run(nil, client: client)

    assert_equal ['web01.corp.example.com'], usable.map(&:address)
  end

  test 'entries carry class and domain controller flags' do
    client = FakeClient.new([
      entry(dns: 'dc01.corp.example.com', os: 'Microsoft Windows Server 2019 Standard', gid: 516),
      entry(dns: 'web01.corp.example.com', os: 'Microsoft Windows 10 Pro'),
      entry(dns: 'box01.corp.example.com', os: 'Ubuntu 22.04 LTS'),
    ])

    usable, _present, _unnamed = AdQuery.run(nil, client: client)
    by_address = usable.index_by(&:address)

    assert_equal :server, by_address['dc01.corp.example.com'].host_class
    assert by_address['dc01.corp.example.com'].domain_controller
    assert_equal :workstation, by_address['web01.corp.example.com'].host_class
    refute by_address['web01.corp.example.com'].domain_controller
    assert_equal :unknown, by_address['box01.corp.example.com'].host_class
  end

  # The read-only DC group is a domain controller for practical purposes: it is
  # still a DC, and still worth flagging before bulk-enabling WinRM against it.
  test 'the read-only domain controller group is flagged too' do
    client = FakeClient.new([
      entry(dns: 'rodc01.corp.example.com', os: 'Microsoft Windows Server 2019 Standard', gid: 517),
    ])
    usable, _present, _unnamed = AdQuery.run(nil, client: client)

    assert usable.first.domain_controller
  end

  # AD caps a search at MaxPageSize (1000 by default) and truncation is silent:
  # the operator sees a plausible list with no hint that half the fleet is
  # missing. net-ldap pages with RFC 2696 cookies as long as no :size limit is
  # passed, so the guard here is that the requested attribute list is narrow and
  # no size limit is part of the call.
  test 'the attribute list is narrow and named, never a wildcard' do
    client = FakeClient.new([entry(dns: 'web01.corp.example.com', os: 'Microsoft Windows 10 Pro')])
    AdQuery.run(nil, client: client)

    refute_includes client.attributes, '*'
    # Large and useless here: security descriptors and backward links dominate a
    # wildcard fetch on a large domain.
    refute_includes client.attributes, 'nTSecurityDescriptor'
    assert_includes client.attributes, 'dNSHostName'
    assert_includes client.attributes, 'operatingSystem'
  end

  test 'the filter the client receives reflects the requested host filter' do
    client = FakeClient.new([])
    AdQuery.run(nil, host_filter: 'servers', client: client)

    assert_equal AdQuery.build_filter(host_filter: 'servers'), client.filter
  end
end
