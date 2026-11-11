require 'test_helper'

# A WindowsTarget holds a domain credential. The screens are rights-gated, but
# a browser is not a trusted place for credential material: it lands in page
# HTML, history, proxy logs, and is readable by any XSS on the page. And unlike
# a bcrypt hash, this one is reversible -- Rails' encrypts is there to protect
# the database at rest, not to make the value safe to display.
#
# Same shape as CredentialExposureTest for users, plus the JSON paths, which the
# users screens do not have.
class WindowsTargetCredentialExposureTest < ActionDispatch::IntegrationTest
  SECRET = 'S3cret-Domain-Pw!'.freeze

  setup do
    admin_right = Right.create!(name: 'Admin', description: 'admin')
    viewer_right = Right.create!(name: 'Viewer', description: 'viewer')
    role = Role.create!(name: "WinAdmins#{SecureRandom.hex(6)}", description: 'admins')
    role.rights << admin_right
    role.rights << viewer_right
    admin = User.create!(username: "wadmin#{SecureRandom.hex(6)}", attempts: 0)
    admin.roles << role
    cookies[:sessionID] = Session.create!(user: admin, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    @target = WindowsTarget.create!(
      address: "dc01-#{SecureRandom.hex(4)}.example.com",
      polling_priority: PollingPriority.find_by(name: 'Priority 1'),
      event_logs: 'Application',
      username: 'svc-poll',
      password: SECRET)
  end

  # Sanity check on the fixture: if encryption were off, every assertion below
  # would pass for the wrong reason.
  test 'the fixture really stores ciphertext' do
    raw = WindowsTarget.connection.select_value(
      "select password from windows_targets where id = #{@target.id}")

    assert_not_nil raw, 'the encrypted column must actually be written'
    refute_includes raw, SECRET
  end

  test 'no HTML page emits the credential' do
    %w[/windows_targets /windows_targets.json].each do |path|
      get "https://www.example.com#{path}"
      assert_response :success
      refute_includes response.body, SECRET, "#{path} must not render the credential"
    end

    get "https://www.example.com/windows_targets/#{@target.id}"
    assert_response :success
    refute_includes response.body, SECRET

    get "https://www.example.com/windows_targets/#{@target.id}.json"
    assert_response :success
    refute_includes response.body, SECRET

    get "https://www.example.com/windows_targets/#{@target.id}/edit"
    assert_response :success
    refute_includes response.body, SECRET
  end

  test 'the JSON shows whether a credential exists, never the credential' do
    get "https://www.example.com/windows_targets/#{@target.id}.json"
    body = JSON.parse(response.body)

    assert_equal true, body['credential_present']
    refute body.key?('password')
  end

  test 'the edit form renders a blank, masked password field' do
    get "https://www.example.com/windows_targets/#{@target.id}/edit"
    assert_response :success

    field = response.body[/<input[^>]*name="windows_target\[password\]"[^>]*>/].to_s
    refute_empty field, 'the form must still offer a password field'
    assert_match(/type="password"/, field, 'the field must be masked')
    refute_match(/value="#{Regexp.escape(SECRET)}/, field, 'it must not be prefilled')
  end

  # The functional half: an untouched password field submits blank, and treating
  # blank as "set it to blank" would wipe a working credential on any unrelated
  # edit -- which would show up as a host silently going quiet.
  test 'editing without touching the password keeps the credential' do
    patch "https://www.example.com/windows_targets/#{@target.id}", params: {
      windows_target: { address: @target.address, name: 'renamed',
                        polling_priority_id: @target.polling_priority_id,
                        event_logs: 'Application,System', username: 'svc-poll',
                        enabled: true, password: '' }
    }
    assert_response :redirect

    assert_equal SECRET, @target.reload.password
    assert_equal 'renamed', @target.name
  end

  test 'a supplied password replaces the stored one' do
    patch "https://www.example.com/windows_targets/#{@target.id}", params: {
      windows_target: { address: @target.address,
                        polling_priority_id: @target.polling_priority_id,
                        event_logs: 'Application', username: 'svc-poll',
                        enabled: true, password: 'rotated-pw' }
    }
    assert_response :redirect

    assert_equal 'rotated-pw', @target.reload.password
  end

  # A Viewer may read the list but must not add hosts, change what DAD polls,
  # or point the poller at a new address with new credentials.
  test 'a Viewer cannot write a Windows target' do
    viewer_right = Right.find_by(name: 'Viewer')
    role = Role.create!(name: "WinViewers#{SecureRandom.hex(6)}", description: 'viewers')
    role.rights << viewer_right
    viewer = User.create!(username: "wviewer#{SecureRandom.hex(6)}", attempts: 0)
    viewer.roles << role
    cookies[:sessionID] = Session.create!(user: viewer, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    get 'https://www.example.com/windows_targets'
    assert_response :success

    get 'https://www.example.com/windows_targets/new'
    assert_response :redirect

    post 'https://www.example.com/windows_targets', params: {
      windows_target: { address: 'rogue.example.com',
                        polling_priority_id: PollingPriority.find_by(name: 'Priority 1').id,
                        event_logs: 'Security', username: 'x', password: 'y' }
    }
    assert_response :redirect
    refute WindowsTarget.exists?(address: 'rogue.example.com'),
           'a Viewer must not be able to register a host for DAD to connect to'

    # poll_now makes an outbound connection using the stored credential, so it is
    # an Admin action too. Asserted against the policy rather than by POSTing:
    # a redirect alone would also be produced by poll_now's own rescue of an
    # unreachable host, so the response code cannot tell refusal from failure.
    assert_equal %w[Admin], ApplicationController.required_rights('windows_targets', 'poll_now')
  end

  # Priority bands are the guarantee a host is polled under. A Viewer can read
  # them next to the hosts relying on them, but widening one loosens collection.
  test 'a Viewer can read priorities but not retune them' do
    viewer_right = Right.find_by(name: 'Viewer')
    role = Role.create!(name: "WinViewers2#{SecureRandom.hex(6)}", description: 'viewers')
    role.rights << viewer_right
    viewer = User.create!(username: "wviewer2#{SecureRandom.hex(6)}", attempts: 0)
    viewer.roles << role
    cookies[:sessionID] = Session.create!(user: viewer, expiry: Time.now + 1.hour,
                                          session_hash: SecureRandom.hex(16)).session_hash

    get 'https://www.example.com/polling_priorities'
    assert_response :success

    p1 = PollingPriority.find_by(name: 'Priority 1')
    get "https://www.example.com/polling_priorities/#{p1.id}/edit"
    assert_response :redirect

    patch "https://www.example.com/polling_priorities/#{p1.id}", params: {
      polling_priority: { name: p1.name, rank: p1.rank,
                          min_interval_secs: 60, max_interval_secs: 86_400 }
    }
    assert_response :redirect
    assert_equal 300, p1.reload.max_interval_secs, 'the band must not have widened'
  end
end
