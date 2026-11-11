require 'test_helper'

# AdImportBatch exists to enforce one invariant: apply() may only REMOVE from the
# stored candidate set, never add to it.
#
# Why that matters: a WindowsTarget row makes this server connect OUT to `address`
# carrying a domain credential. If apply() took host names from the submitted
# form, a crafted POST would create a target for any host an attacker named and
# hand it our WinRM credential -- SSRF with a domain login attached, arriving
# through a form whose only visible affordance is unchecking boxes. So the
# candidate set is written server-side at preview time and the submitted
# selection is intersected with it.
class AdImportBatchTest < ActiveSupport::TestCase
  def connection(overrides = {})
    ActiveDirectoryConnection.create!({
      name: "corp-#{SecureRandom.hex(6)}",
      host: 'dc01.corp.example.com',
      port: 636,
      bind_dn: 'CN=svc-dad,OU=Service,DC=corp,DC=example,DC=com',
      password: 'bind-pw',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      poll_username: 'svc-poll',
      poll_password: 'winrm-pw',
      event_logs: 'Application,System'
    }.merge(overrides))
  end

  def candidate(address, opts = {})
    {
      'address' => address,
      'name' => opts[:name] || address.split('.').first,
      'operating_system' => opts[:os] || 'Microsoft Windows 10 Pro',
      'host_class' => opts[:host_class] || 'workstation',
      'domain_controller' => opts.fetch(:domain_controller, false),
      'already_present' => opts.fetch(:already_present, false)
    }
  end

  def batch(candidates, overrides = {})
    AdImportBatch.create!({
      active_directory_connection: connection,
      host_filter: 'all',
      candidates: candidates
    }.merge(overrides))
  end

  # ---- the security boundary ----------------------------------------------

  # The headline case. A POST naming a host the query never returned must create
  # nothing, no matter how it is phrased.
  test 'apply cannot add a host the query never offered' do
    b = batch([candidate('web01.corp.example.com'), candidate('web02.corp.example.com')])

    result = b.apply(['web01.corp.example.com', 'attacker.example.com',
                      '169.254.169.254', 'localhost'])

    assert_equal ['web01.corp.example.com'], result[:added]
    assert_equal ['attacker.example.com', '169.254.169.254', 'localhost'], result[:rejected]
    assert_equal ['web02.corp.example.com'], result[:deselected]

    assert WindowsTarget.exists?(address: 'web01.corp.example.com')
    ['attacker.example.com', '169.254.169.254', 'localhost'].each do |host|
      refute WindowsTarget.exists?(address: host),
             "#{host} was never offered by the query and must not be created"
    end
  end

  # A rejected name must not be smuggled in through case or whitespace either.
  test 'apply does not launder a rejected name through normalization' do
    b = batch([candidate('web01.corp.example.com')])

    result = b.apply([' WEB01.CORP.EXAMPLE.COM ', 'evil.example.com'])

    # The FQDN as stored is the only accepted form; the uppercase variant is not
    # in the candidate set, so it is rejected rather than matched loosely.
    assert_empty result[:added]
    assert_equal ['WEB01.CORP.EXAMPLE.COM', 'evil.example.com'], result[:rejected]
    refute WindowsTarget.exists?(address: 'evil.example.com')
  end

  # Unchecking everything is a legitimate answer, not an error.
  test 'apply with an empty selection adds nothing and records the batch' do
    b = batch([candidate('web01.corp.example.com')])
    result = b.apply([])

    assert_empty result[:added]
    assert_equal ['web01.corp.example.com'], result[:deselected]
    refute WindowsTarget.exists?(address: 'web01.corp.example.com')
    assert b.reload.applied?
    assert_equal 0, b.added_count
  end

  test 'apply ignores blank and duplicate entries in the selection' do
    b = batch([candidate('web01.corp.example.com'), candidate('web02.corp.example.com')])
    result = b.apply(['web01.corp.example.com', 'web01.corp.example.com', '', '   ', nil])

    assert_equal ['web01.corp.example.com'], result[:added]
    assert_equal 1, WindowsTarget.where(address: 'web01.corp.example.com').count
  end

  # A batch that creates credential-bearing rows should not be replayable: a
  # second POST would re-run the import against a stale candidate list.
  test 'a batch applies once' do
    b = batch([candidate('web01.corp.example.com')])
    b.apply(['web01.corp.example.com'])

    assert b.reload.applied?
    assert_raises(RuntimeError) { b.apply(['web01.corp.example.com']) }
  end

  # ---- defaults applied to imported hosts ---------------------------------

  # An imported host has to be pollable the moment it exists. If the connection's
  # priority, channels, or credential did not carry over, "add them for polling"
  # would produce rows that can never poll.
  test 'imported targets inherit the connection defaults' do
    conn = connection(event_logs: 'Application,Setup',
                      polling_priority: PollingPriority.find_by(name: 'Priority 3'))
    b = AdImportBatch.create!(active_directory_connection: conn,
                              host_filter: 'all',
                              candidates: [candidate('web01.corp.example.com')])

    b.apply(['web01.corp.example.com'])
    target = WindowsTarget.find_by(address: 'web01.corp.example.com')

    assert_not_nil target
    assert_equal 'Application,Setup', target.event_logs
    assert_equal PollingPriority.find_by(name: 'Priority 3').id, target.polling_priority_id
    assert_equal 'svc-poll', target.username
    assert_equal 'winrm-pw', target.password, 'the polling credential must carry over'
    assert target.enabled?, 'an imported host should poll without a second step'
  end

  # The credential must not travel through the browser on the way back from the
  # preview page -- it is read from the connection at apply time.
  test 'the polling credential is never taken from the submitted selection' do
    b = batch([candidate('web01.corp.example.com')])
    b.apply(['web01.corp.example.com', 'password' => 'evil'])

    target = WindowsTarget.find_by(address: 'web01.corp.example.com')
    assert_equal 'winrm-pw', target.password
    refute_equal 'evil', target.password
  end

  # ---- already-present handling -------------------------------------------

  # A target may have been created by hand between preview and apply. Two rows
  # for one host would double-poll it and interleave two offset states.
  test 'apply skips a host that became a target after the preview' do
    b = batch([candidate('web01.corp.example.com')])
    WindowsTarget.create!(address: 'web01.corp.example.com', name: 'added by hand',
                          polling_priority: PollingPriority.find_by(name: 'Priority 1'),
                          event_logs: 'Application')

    result = b.apply(['web01.corp.example.com'])

    assert_empty result[:added]
    assert(result[:skipped].any? { |s| s.include?('web01.corp.example.com') })
    assert_equal 1, WindowsTarget.where(address: 'web01.corp.example.com').count
  end

  # AD returns FQDNs; an operator typing a host by hand uses the short name.
  test 'apply skips an FQDN whose short name is already a target' do
    b = batch([candidate('web01.corp.example.com')])
    WindowsTarget.create!(address: 'web01', name: 'short form',
                          polling_priority: PollingPriority.find_by(name: 'Priority 1'),
                          event_logs: 'Application')

    result = b.apply(['web01.corp.example.com'])

    assert_empty result[:added]
    assert_equal 1, WindowsTarget.count
  end

  # Candidates flagged at preview time are not offered at all, so selecting one
  # explicitly is a rejection, not a re-add.
  test 'a candidate already present at preview time cannot be selected' do
    b = batch([candidate('web01.corp.example.com', already_present: true)])

    result = b.apply(['web01.corp.example.com'])

    assert_empty result[:added]
    assert_equal ['web01.corp.example.com'], result[:rejected]
  end

  # ---- partial failure ----------------------------------------------------

  # One bad host must not cost the other 399. Same principle as one unreadable
  # event-log channel not costing a host its other channels.
  test 'one invalid host does not abort the rest of the import' do
    b = AdImportBatch.create!(
      active_directory_connection: connection,
      host_filter: 'all',
      candidates: [candidate('good01.corp.example.com'),
                   candidate('bad host name!', name: 'bad'),
                   candidate('good02.corp.example.com')])

    result = b.apply(['good01.corp.example.com', 'bad host name!', 'good02.corp.example.com'])

    assert_equal %w[good01.corp.example.com good02.corp.example.com], result[:added]
    assert_equal 2, b.reload.added_count
    assert b.applied?
    assert_equal 2, WindowsTarget.count
  end

  # ---- candidate storage --------------------------------------------------

  test 'candidates round-trip through JSON' do
    b = batch([candidate('web01.corp.example.com', os: 'Microsoft Windows Server 2019',
                         host_class: 'server', domain_controller: true)])

    reloaded = AdImportBatch.find(b.id)
    assert_equal 1, reloaded.candidates.size
    assert reloaded.candidates.first['domain_controller']
    assert_equal 'server', reloaded.candidates.first['host_class']
  end

  # YAML on a stored blob is a deserialization footgun; a corrupt column must
  # degrade to an empty list rather than raise or deserialize an object.
  test 'corrupt candidate JSON reads as empty rather than raising' do
    b = batch([candidate('web01.corp.example.com')])
    AdImportBatch.connection.execute(
      "update ad_import_batches set candidates = 'not json' where id = #{b.id}")

    assert_empty AdImportBatch.find(b.id).candidates
  end

  test 'a batch with no candidates is invalid' do
    b = AdImportBatch.new(active_directory_connection: connection,
                          host_filter: 'all', candidates: [])
    refute b.valid?
    assert b.errors[:candidates].any?

    blank = AdImportBatch.new(active_directory_connection: connection,
                              host_filter: 'all')
    refute blank.valid?
  end

  test 'host_filter is restricted to the known values' do
    %w[all workstations servers].each do |ok|
      assert AdImportBatch.new(active_directory_connection: connection,
                               host_filter: ok,
                               candidates: [candidate('web01')]).valid?,
             "expected #{ok} to be valid"
    end
    refute AdImportBatch.new(active_directory_connection: connection,
                             host_filter: 'everything',
                             candidates: [candidate('web01')]).valid?
  end

  # new_hosts / already_present drive the preview page, and the preview is what
  # an operator trusts to decide what got imported.
  test 'new_hosts excludes candidates already present' do
    b = batch([candidate('web01.corp.example.com'),
               candidate('sql01.corp.example.com', already_present: true)])

    assert_equal ['web01.corp.example.com'], b.new_hosts.map { |c| c['address'] }
    assert_equal ['sql01.corp.example.com'], b.already_present.map { |c| c['address'] }
  end
end
