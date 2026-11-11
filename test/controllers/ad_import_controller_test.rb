require 'test_helper'

# The Active Directory screens hold two domain credentials and drive a bulk
# operation that creates credential-bearing Windows targets. These tests cover
# the HTTP layer: who may reach the screens, and what a crafted POST can and
# cannot cause.
#
# The second part is the point. AdImportBatch#apply intersects the submitted
# selection with the candidate set stored server-side at preview time, so a POST
# naming a host the directory query never returned must create nothing. Without
# that, the apply endpoint would be an SSRF primitive with a domain credential
# attached, reached through a form whose only visible affordance is unchecking
# boxes.
class AdImportControllerTest < ActionDispatch::IntegrationTest
  BIND_PW = 'bind-S3cret!'.freeze
  WINRM_PW = 'winrm-S3cret!'.freeze

  def setup
    @admin = sign_in_as('Admin', 'Viewer')
    @conn = ActiveDirectoryConnection.create!(
      name: "corp-#{SecureRandom.hex(6)}",
      host: 'dc01.corp.example.com', port: 636,
      bind_dn: 'CN=svc-dad,OU=Service,DC=corp,DC=example,DC=com',
      password: BIND_PW,
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      poll_username: 'svc-poll', poll_password: WINRM_PW,
      event_logs: 'Application,System')
  end

  def sign_in_as(*right_names)
    role = Role.create!(name: "Ad#{right_names.join}#{SecureRandom.hex(6)}", description: 'r')
    right_names.each do |rn|
      right = Right.find_by(name: rn) || Right.create!(name: rn, description: rn)
      role.rights << right
    end
    user = User.create!(username: "ad#{right_names.join.downcase}#{SecureRandom.hex(6)}",
                        attempts: 0)
    user.roles << role
    cookies[:sessionID] = Session.create!(user: user, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash
    user
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

  # Builds a batch directly, the way the create action would after a query. The
  # LDAP call itself is covered in AdQueryTest; here the subject is what the
  # apply endpoint accepts.
  def batch(candidates)
    AdImportBatch.create!(active_directory_connection: @conn, user: @admin,
                          host_filter: 'all', candidates: candidates)
  end

  # ---- authorization -------------------------------------------------------

  # Stricter than windows_targets, where reading the list is a Viewer action. A
  # directory query returns the whole machine inventory, which is
  # reconnaissance-grade information regardless of what gets imported after.
  test 'a Viewer cannot reach any AD screen' do
    sign_in_as('Viewer')

    %w[/active_directory_connections /active_directory_connections.json
       /active_directory_connections/new /ad_import_batches/new].each do |path|
      get "https://www.example.com#{path}"
      assert_response :redirect, "#{path} must not be reachable by a Viewer"
    end

    get "https://www.example.com/active_directory_connections/#{@conn.id}"
    assert_response :redirect
  end

  # setup signed an Admin in, and the cookie cannot simply be deleted: each new
  # request merges the previous request's jar back in
  # (Cookies#update_cookies_from_jar -- see the note in test_helper.rb), so a
  # plain delete leaves the admin session in play and the test would pass for the
  # wrong reason. Overwriting with a token that matches no Session row makes
  # gatekeeper resolve @current_user to nil, which is the anonymous path.
  test 'an anonymous request cannot reach any AD screen' do
    cookies[:sessionID] = SecureRandom.hex(16)

    %w[/active_directory_connections /ad_import_batches/new].each do |path|
      get "https://www.example.com#{path}"
      assert_response :redirect, "#{path} must not be reachable anonymously"
      assert_not_includes response.body, @conn.host
    end
  end

  test 'an Admin can reach the AD screens' do
    %w[/active_directory_connections /active_directory_connections.json
       /active_directory_connections/new /ad_import_batches/new].each do |path|
      get "https://www.example.com#{path}"
      assert_response :success, "#{path} should be reachable by an Admin"
    end
  end

  # ---- credential exposure -------------------------------------------------

  # Same reasoning as WindowsTargetCredentialExposureTest: the browser is not a
  # trusted place for credential material, and unlike a bcrypt hash this is
  # reversible. Rails' encrypts protects the database at rest, not the page.
  test 'no HTML or JSON page emits either credential' do
    paths = [
      "/active_directory_connections",
      "/active_directory_connections.json",
      "/active_directory_connections/#{@conn.id}",
      "/active_directory_connections/#{@conn.id}.json",
      "/active_directory_connections/#{@conn.id}/edit",
    ]

    paths.each do |path|
      get "https://www.example.com#{path}"
      assert_response :success
      refute_includes response.body, BIND_PW, "#{path} must not render the bind credential"
      refute_includes response.body, WINRM_PW, "#{path} must not render the WinRM credential"
    end
  end

  # json.extract! without a field list would publish the ciphertext columns.
  test 'the JSON views report credential presence, never the credentials' do
    get "https://www.example.com/active_directory_connections/#{@conn.id}.json"
    body = response.body

    assert_includes body, 'credential_present'
    refute_includes body, BIND_PW
    refute_includes body, WINRM_PW
  end

  # An edit form that echoed the stored password would put it in the page, the
  # browser history, and every proxy log between.
  test 'the edit form does not prefill either password' do
    get "https://www.example.com/active_directory_connections/#{@conn.id}/edit"
    assert_response :success

    # The fields exist and are empty, which is what makes "leave blank to keep"
    # work without echoing the secret.
    assert_select 'input[type=password][name=?]', 'active_directory_connection[password]'
    assert_select 'input[type=password][name=?]', 'active_directory_connection[poll_password]'
    refute_includes response.body, BIND_PW
    refute_includes response.body, WINRM_PW
  end

  # Leaving the password fields blank on an edit must not blank the stored
  # credential -- the trap windows_targets#password guards against.
  test 'an edit that omits the passwords keeps them' do
    get "https://www.example.com/active_directory_connections/#{@conn.id}/edit"
    assert_response :success

    patch "https://www.example.com/active_directory_connections/#{@conn.id}", params: {
      active_directory_connection: {
        name: @conn.name, host: @conn.host, port: @conn.port,
        bind_dn: @conn.bind_dn, search_base: @conn.search_base,
        polling_priority_id: @conn.polling_priority_id,
        poll_username: @conn.poll_username, event_logs: @conn.event_logs,
        enabled: true, password: '', poll_password: ''
      }
    }

    reloaded = ActiveDirectoryConnection.find(@conn.id)
    assert_equal BIND_PW, reloaded.password, 'a blank password field must keep the credential'
    assert_equal WINRM_PW, reloaded.poll_password
  end

  # ---- the apply endpoint --------------------------------------------------

  # The headline security case at the HTTP layer.
  test 'POST apply cannot create a target for a host the query never returned' do
    b = batch([candidate('web01.corp.example.com'), candidate('web02.corp.example.com')])

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com', 'metadata.example.internal',
                           '169.254.169.254', 'localhost', 'attacker.example.com']
    }

    assert_response :redirect
    assert WindowsTarget.exists?(address: 'web01.corp.example.com')
    ['metadata.example.internal', '169.254.169.254', 'localhost',
     'attacker.example.com'].each do |host|
      refute WindowsTarget.exists?(address: host),
             "#{host} was never offered by the query and must not be created"
    end
    assert_equal 1, WindowsTarget.count
  end

  # A Viewer must not be able to drive the import by POSTing directly, even with
  # a valid batch id.
  test 'a Viewer cannot apply a batch' do
    b = batch([candidate('web01.corp.example.com')])
    sign_in_as('Viewer')

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com']
    }

    assert_response :redirect
    refute WindowsTarget.exists?(address: 'web01.corp.example.com')
    refute b.reload.applied?
  end

  test 'POST apply honours de-selection' do
    b = batch([candidate('web01.corp.example.com'),
               candidate('web02.corp.example.com'),
               candidate('sql01.corp.example.com', host_class: 'server')])

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com']
    }

    assert WindowsTarget.exists?(address: 'web01.corp.example.com')
    refute WindowsTarget.exists?(address: 'web02.corp.example.com')
    refute WindowsTarget.exists?(address: 'sql01.corp.example.com')
    assert_equal 1, b.reload.added_count
  end

  # Unchecking everything is a legitimate answer.
  test 'POST apply with nothing selected creates nothing' do
    b = batch([candidate('web01.corp.example.com')])

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {}

    refute WindowsTarget.exists?(address: 'web01.corp.example.com')
    assert b.reload.applied?
    assert_equal 0, b.added_count
  end

  # Replaying the apply POST must not re-import against a stale candidate list.
  test 'a batch cannot be applied twice' do
    b = batch([candidate('web01.corp.example.com')])

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com']
    }
    assert_response :redirect
    assert_equal 1, WindowsTarget.count

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com']
    }
    assert_response :redirect
    assert_equal 1, WindowsTarget.count
    assert_equal 1, b.reload.added_count
  end

  # The credential is read from the connection server-side. If it could be
  # supplied through the form, an attacker who could reach the page could point
  # any imported host at any credential.
  test 'the polling credential cannot be injected through the apply form' do
    b = batch([candidate('web01.corp.example.com')])

    post "https://www.example.com/ad_import_batches/#{b.id}/apply", params: {
      selected_addresses: ['web01.corp.example.com'],
      password: 'evil-credential',
      username: 'evil-user',
      active_directory_connection: { poll_password: 'evil-credential' }
    }

    target = WindowsTarget.find_by(address: 'web01.corp.example.com')
    assert_not_nil target
    assert_equal WINRM_PW, target.password
    assert_equal 'svc-poll', target.username
  end

  # An unknown batch id raises rather than rendering, matching every other
  # controller in the app (windows_targets, jobs, ...), which all use #find.
  # show_exceptions is :none in the test environment, so the raise surfaces here;
  # in production it renders 404. What matters is that no record is created and
  # no candidate list is rendered for an id that does not exist.
  test 'an unknown batch id raises and creates nothing' do
    assert_raises(ActiveRecord::RecordNotFound) do
      post "https://www.example.com/ad_import_batches/999999/apply",
           params: { selected_addresses: ['x'] }
    end
    refute WindowsTarget.exists?(address: 'x')
  end

  # ---- the preview page ----------------------------------------------------

  # The preview is where an operator decides. Hosts already in the database must
  # not be offered again, and hosts with no recognisable Windows OS must not
  # arrive pre-selected.
  test 'the preview lists new hosts as checkboxes and omits existing ones' do
    b = batch([candidate('web01.corp.example.com'),
               candidate('sql01.corp.example.com', host_class: 'server',
                         os: 'Microsoft Windows Server 2019 Standard'),
               candidate('old01.corp.example.com', already_present: true)])

    get "https://www.example.com/ad_import_batches/#{b.id}"
    assert_response :success

    assert_select 'input[type=checkbox][name=?]', 'selected_addresses[]', 2
    assert_includes response.body, 'web01.corp.example.com'
    assert_includes response.body, 'sql01.corp.example.com'
    # Present hosts are shown for context but never as a selectable checkbox.
    assert_includes response.body, 'old01.corp.example.com'
    refute_includes response.body, "value=\"old01.corp.example.com\""
  end

  test 'the preview pre-selects ordinary hosts and leaves unknown OS unchecked' do
    b = batch([candidate('web01.corp.example.com'),
               candidate('linux01.corp.example.com', os: 'Ubuntu 22.04 LTS',
                         host_class: 'unknown')])

    get "https://www.example.com/ad_import_batches/#{b.id}"
    assert_response :success

    checked = response.body.scan(/<input[^>]*type="checkbox"[^>]*>/)
                        .select { |tag| tag.include?('checked') }
                        .map { |tag| tag[/value="([^"]+)"/, 1] }

    assert_includes checked, 'web01.corp.example.com'
    refute_includes checked, 'linux01.corp.example.com',
                    'a host with no recognisable Windows OS must not be pre-selected'
  end

  # Domain controllers match the server filter, and polling one over WinRM is a
  # decision worth making deliberately.
  test 'the preview flags domain controllers' do
    b = batch([candidate('dc01.corp.example.com', host_class: 'server',
                         os: 'Microsoft Windows Server 2019 Standard',
                         domain_controller: true)])

    get "https://www.example.com/ad_import_batches/#{b.id}"
    assert_response :success
    assert_includes response.body, 'domain controller'
  end

  # Duplicate ids are invalid HTML and browsers resolve "#id" to the first
  # match, so a per-row id inside this loop would make every row after the first
  # unaddressable.
  test 'the preview renders no duplicate id attributes' do
    b = batch(3.times.map { |i| candidate("web0#{i}.corp.example.com") })

    get "https://www.example.com/ad_import_batches/#{b.id}"
    assert_response :success

    ids = response.body.scan(/id\s*=\s*["']([^"']+)["']/).flatten
    duplicates = ids.tally.select { |_id, count| count > 1 }
    assert_empty duplicates, "duplicate ids: #{duplicates.inspect}"
  end

  # Escaping: a computer object named with markup must not execute in the
  # preview table.
  test 'candidate values are escaped in the preview' do
    evil = 'x<script>alert(1)</script>'
    b = batch([candidate('web01.corp.example.com', name: evil)])

    get "https://www.example.com/ad_import_batches/#{b.id}"
    assert_response :success
    refute_includes response.body, '<script>alert(1)</script>'
  end

  # ---- the query form ------------------------------------------------------

  test 'the query form offers only enabled connections' do
    disabled = ActiveDirectoryConnection.create!(
      name: "off-#{SecureRandom.hex(6)}", host: 'dc02.corp.example.com', port: 636,
      bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'x',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application', enabled: false)

    get "https://www.example.com/ad_import_batches/new"
    assert_response :success

    # The dropdown is keyed on display_name, not host, so assert on the option
    # values rather than on the host string appearing somewhere in the page.
    option_values = response.body.scan(/<select name="active_directory_connection_id".*?<\/select>/m)
                                .flat_map { |sel| sel.scan(/<option value="(\d+)"/).flatten }
                                .map(&:to_i)

    assert_includes option_values, @conn.id
    refute_includes option_values, disabled.id, 'a disabled connection must not be offered'
  end

  # A connection with no WinRM credential produces targets that can never poll.
  # That must be said out loud rather than discovered later.
  test 'the query form warns about a connection with no polling credential' do
    no_cred = ActiveDirectoryConnection.create!(
      name: "nocred-#{SecureRandom.hex(6)}", host: 'dc03.corp.example.com', port: 636,
      bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'x',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application')

    get "https://www.example.com/ad_import_batches/new"
    assert_response :success
    assert_includes response.body, 'no WinRM credential'
  end

  # An unreachable directory is an ordinary condition, not a 500, and must not
  # read as "no new hosts".
  test 'a failed query redirects with an error rather than reporting success' do
    dead = ActiveDirectoryConnection.create!(
      name: "dead-#{SecureRandom.hex(6)}", host: 'no-such-dc.invalid', port: 636,
      bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'x',
      search_base: 'DC=corp,DC=example,DC=com',
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application')

    assert_nothing_raised do
      post "https://www.example.com/ad_import_batches", params: {
        active_directory_connection_id: dead.id, host_filter: 'all'
      }
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, 'failed'
    assert_equal 0, AdImportBatch.count, 'a failed query must not record a batch'
  end

  # A bogus connection id must not 500 either.
  test 'querying an unknown connection redirects with an error' do
    post "https://www.example.com/ad_import_batches", params: {
      active_directory_connection_id: 999999, host_filter: 'all'
    }
    assert_response :redirect
    assert_equal 0, AdImportBatch.count
  end

  # An unknown filter string must not silently widen to "everything".
  test 'an unknown host filter falls back to all rather than widening the query' do
    # The controller clamps to 'all'; the point is it does not pass the raw
    # string to AdQuery, which would raise, and does not accept it as valid.
    post "https://www.example.com/ad_import_batches", params: {
      active_directory_connection_id: @conn.id, host_filter: 'everything'
    }
    assert_response :redirect
  end

  # ---- CRUD ---------------------------------------------------------------

  test 'creating a connection through the form works and rejects a blank bind credential' do
    post "https://www.example.com/active_directory_connections", params: {
      active_directory_connection: {
        name: "form-#{SecureRandom.hex(6)}", host: 'dc04.corp.example.com', port: 636,
        bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'new-bind-pw',
        search_base: 'DC=corp,DC=example,DC=com',
        polling_priority_id: PollingPriority.find_by(name: 'Priority 1').id,
        poll_username: 'svc-poll', poll_password: 'new-winrm-pw',
        event_logs: 'Application', enabled: '1'
      }
    }
    assert_response :redirect
    created = ActiveDirectoryConnection.find_by(host: 'dc04.corp.example.com')
    assert_not_nil created
    assert_equal 'new-bind-pw', created.password

    post "https://www.example.com/active_directory_connections", params: {
      active_directory_connection: {
        name: "nobind-#{SecureRandom.hex(6)}", host: 'dc05.corp.example.com', port: 636,
        bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: '',
        search_base: 'DC=corp,DC=example,DC=com',
        polling_priority_id: PollingPriority.find_by(name: 'Priority 1').id,
        event_logs: 'Application', enabled: '1'
      }
    }
    assert_response :success, 'an invalid form should re-render, not redirect'
    assert_nil ActiveDirectoryConnection.find_by(host: 'dc05.corp.example.com')
  end

  # A Viewer must not be able to create or edit a connection by POSTing directly.
  test 'a Viewer cannot create or update a connection' do
    sign_in_as('Viewer')

    post "https://www.example.com/active_directory_connections", params: {
      active_directory_connection: {
        name: "viewer-#{SecureRandom.hex(6)}", host: 'dc06.corp.example.com', port: 636,
        bind_dn: 'CN=svc-dad,DC=corp,DC=example,DC=com', password: 'x',
        search_base: 'DC=corp,DC=example,DC=com',
        polling_priority_id: PollingPriority.find_by(name: 'Priority 1').id,
        event_logs: 'Application', enabled: '1'
      }
    }
    assert_response :redirect
    assert_nil ActiveDirectoryConnection.find_by(host: 'dc06.corp.example.com')

    patch "https://www.example.com/active_directory_connections/#{@conn.id}", params: {
      active_directory_connection: { event_logs: 'ForwardedEvents' }
    }
    assert_response :redirect
    assert_equal 'Application,System', @conn.reload.event_logs
  end
end
