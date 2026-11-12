require 'test_helper'

# An ActiveDirectoryConnection holds two domain credentials and describes how to
# reach a directory. The validations here are what keep a misconfiguration from
# reading as a successful import of nothing.
class ActiveDirectoryConnectionTest < ActiveSupport::TestCase
  def valid_attrs(overrides = {})
    {
      name: "corp-#{SecureRandom.hex(6)}",
      host: 'dc01.corp.example.com',
      port: 636,
      bind_dn: 'CN=svc-dad,OU=Service Accounts,DC=corp,DC=example,DC=com',
      password: 'bind-pw',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application,System'
    }.merge(overrides)
  end

  test 'a complete connection is valid' do
    assert ActiveDirectoryConnection.new(valid_attrs).valid?
  end

  # An anonymous bind usually returns nothing useful. Without this validation an
  # operator who left the credential blank sees "no new hosts" and reasonably
  # concludes the domain is already fully imported.
  test 'a missing bind credential is rejected rather than binding anonymously' do
    conn = ActiveDirectoryConnection.new(valid_attrs(password: nil))
    refute conn.valid?
    assert_match(/anonymous bind/, conn.errors[:password].join)

    blank = ActiveDirectoryConnection.new(valid_attrs(password: ''))
    refute blank.valid?
  end

  test 'a blank bind DN is rejected' do
    conn = ActiveDirectoryConnection.new(valid_attrs(bind_dn: ''))
    refute conn.valid?
    assert conn.errors[:bind_dn].any?
  end

  # host builds the LDAP(S) URI. A value carrying a scheme or extra path could
  # point the bind somewhere else entirely.
  test 'host rejects anything that could alter the LDAP URI' do
    ['ldap://evil.example.com', 'dc01:389/o', 'dc01 /x', 'dc 01', '', nil].each do |bad|
      conn = ActiveDirectoryConnection.new(valid_attrs(host: bad))
      refute conn.valid?, "expected #{bad.inspect} to be rejected"
    end
  end

  # The DN check is well-formedness, not injection defence: bind_dn and
  # search_base are passed to net-ldap as discrete bind-username and base
  # arguments and never reach a filter string. So the regex only has to reject
  # "you pasted the wrong thing", and must NOT reject legal-but-unusual DNs.
  test 'a DN must open with a recognised attribute type' do
    [
      'DC=corp,DC=example,OU=Some,OU=Place',
      'CN=a b,DC=corp',                       # spaces
      "CN=O'Brien,DC=corp",                   # apostrophes
      'OU=Sales (EU),DC=corp',                # parens are legal per RFC 4514
      'CN=Ünïcödé Näme,DC=corp',              # non-ASCII
      'dc=corp',                              # attribute type is case-insensitive
    ].each do |ok|
      assert ActiveDirectoryConnection.new(valid_attrs(search_base: ok)).valid?,
             "expected #{ok.inspect} to be accepted"
    end

    ['evil=corp', '', '*,DC=corp', '=corp', 'DC'].each do |bad|
      conn = ActiveDirectoryConnection.new(valid_attrs(search_base: bad))
      refute conn.valid?, "expected #{bad.inspect} to be rejected as a search base"
    end
  end

  test 'port is restricted to the two LDAP ports' do
    [389, 636].each do |ok|
      assert ActiveDirectoryConnection.new(valid_attrs(port: ok)).valid?,
             "expected #{ok} to be allowed"
    end
    [nil, 0, 3890, 1389, 88].each do |bad|
      refute ActiveDirectoryConnection.new(valid_attrs(port: bad)).valid?,
             "expected #{bad.inspect} to be rejected"
    end
  end

  # These channel names end up in a wevtutil command line executed on a remote
  # host DAD authenticates to with a domain credential. An unvalidated name is
  # remote command execution.
  test 'event log names that are not safe channel names are rejected' do
    assert ActiveDirectoryConnection.new(
      valid_attrs(event_logs: 'Application,Microsoft-Windows-PowerShell/Operational')).valid?

    ['Application; wevtutil delete', 'Application&&calc.exe', 'Application,`id`',
     'Application,<script>', ',,', ''].each do |bad|
      conn = ActiveDirectoryConnection.new(valid_attrs(event_logs: bad))
      refute conn.valid?, "expected #{bad.inspect} to be rejected"
    end
  end

  test 'name is required and unique' do
    first = ActiveDirectoryConnection.create!(valid_attrs(name: 'dup-corp'))
    dup = ActiveDirectoryConnection.new(valid_attrs(name: 'dup-corp'))
    refute dup.valid?
    assert dup.errors[:name].any?

    refute ActiveDirectoryConnection.new(valid_attrs(name: '')).valid?
    first.destroy
  end

  # ---- credential handling -------------------------------------------------

  # Sanity check on the fixture: if encryption were off, every exposure test
  # below would pass for the wrong reason.
  test 'both credentials are stored as ciphertext' do
    conn = ActiveDirectoryConnection.create!(valid_attrs(password: 'bind-S3cret!',
                                                         poll_username: 'svc-poll',
                                                         poll_password: 'winrm-S3cret!'))

    raw_bind = ActiveDirectoryConnection.connection.select_value(
      "select password from active_directory_connections where id = #{conn.id}")
    raw_poll = ActiveDirectoryConnection.connection.select_value(
      "select poll_password from active_directory_connections where id = #{conn.id}")

    assert_not_nil raw_bind
    refute_includes raw_bind, 'bind-S3cret!'
    assert_not_nil raw_poll
    refute_includes raw_poll, 'winrm-S3cret!'

    # And they still round-trip.
    assert_equal 'bind-S3cret!', ActiveDirectoryConnection.find(conn.id).password
    assert_equal 'winrm-S3cret!', ActiveDirectoryConnection.find(conn.id).poll_password
  ensure
    conn&.destroy
  end

  # ---- behaviour -----------------------------------------------------------

  test 'ldaps? and plaintext_bind? report what the port means' do
    secure = ActiveDirectoryConnection.new(valid_attrs(port: 636))
    assert secure.ldaps?
    refute secure.plaintext_bind?

    starttls = ActiveDirectoryConnection.new(valid_attrs(port: 389))
    refute starttls.ldaps?
    assert starttls.plaintext_bind?
  end

  test 'polling_credential_present? needs both halves' do
    conn = ActiveDirectoryConnection.new(valid_attrs)
    refute conn.polling_credential_present?

    conn.poll_username = 'svc-poll'
    refute conn.polling_credential_present?, 'a username with no password cannot poll'

    conn.poll_password = 'pw'
    assert conn.polling_credential_present?
  end

  test 'import_defaults carries the credential server-side, never through a form' do
    conn = ActiveDirectoryConnection.new(valid_attrs(poll_username: 'svc-poll',
                                                     poll_password: 'winrm-pw',
                                                     event_logs: 'Application,System'))
    defaults = conn.import_defaults

    assert_equal conn.polling_priority_id, defaults[:polling_priority_id]
    assert_equal 'Application,System', defaults[:event_logs]
    assert_equal 'svc-poll', defaults[:username]
    assert_equal 'winrm-pw', defaults[:password]
  end

  test 'log_list splits and trims without dropping the order' do
    conn = ActiveDirectoryConnection.new(valid_attrs(event_logs: 'System, Application ,Setup'))
    assert_equal %w[System Application Setup], conn.log_list
  end

  test 'display_name falls back to the host when the label is blank' do
    # Parenthesised, matching WindowsTarget#display_name: a blank label falls
    # back to the host, and the parens mark it as a fallback rather than a name.
    assert_equal '(dc01.corp.example.com)',
                 ActiveDirectoryConnection.new(valid_attrs(host: 'dc01.corp.example.com',
                                                           name: '  ')).display_name
    assert_equal 'corp', ActiveDirectoryConnection.new(valid_attrs(name: 'corp')).display_name
  end

  test 'enabled excludes disabled connections' do
    on  = ActiveDirectoryConnection.create!(valid_attrs(name: 'on-corp', enabled: true))
    off = ActiveDirectoryConnection.create!(valid_attrs(name: 'off-corp', enabled: false))

    assert_includes ActiveDirectoryConnection.enabled, on
    refute_includes ActiveDirectoryConnection.enabled, off
  ensure
    on&.destroy
    off&.destroy
  end

  # The nav tab and the screens are Admin-only: a query returns the whole machine
  # inventory, which is reconnaissance value before anything is imported.
  test 'hidden? is false for Admin and true for everyone else' do
    conn = ActiveDirectoryConnection.new(valid_attrs(name: 'nav-corp'))

    assert ActiveDirectoryConnection.hidden?(nil)

    viewer_role = Role.create!(name: "NavViewers#{SecureRandom.hex(6)}", description: 'v')
    viewer_role.rights << Right.create!(name: 'Viewer', description: 'v')
    viewer = User.create!(username: "navview#{SecureRandom.hex(6)}", attempts: 0)
    viewer.roles << viewer_role
    assert ActiveDirectoryConnection.hidden?(viewer), 'a Viewer must not see AD screens'

    admin_role = Role.create!(name: "NavAdmins#{SecureRandom.hex(6)}", description: 'a')
    admin_role.rights << Right.create!(name: 'Admin', description: 'a')
    admin = User.create!(username: "navadmin#{SecureRandom.hex(6)}", attempts: 0)
    admin.roles << admin_role
    refute ActiveDirectoryConnection.hidden?(admin)
  ensure
    [conn, viewer, admin].compact.each { |r| r.destroy if r.respond_to?(:destroy) }
  end
end
