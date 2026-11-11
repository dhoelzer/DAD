require 'test_helper'

# The adaptive interval is the substance of the feature: "poll critical systems
# often, poll quiet systems less often, never below the priority floor". These
# tests pin that behaviour against the real bands the migration seeds.
class WindowsTargetTest < ActiveSupport::TestCase
  def priority(name, min_secs, max_secs, rank: PollingPriority.maximum(:rank).to_i + 1)
    PollingPriority.create!(name: name, rank: rank,
                            min_interval_secs: min_secs, max_interval_secs: max_secs)
  end

  def target(priority, rate: 0.0, attrs: {})
    WindowsTarget.create!({
      address: "host-#{SecureRandom.hex(4)}.example.com",
      polling_priority: priority,
      event_logs: 'Application',
      events_per_second: rate,
    }.merge(attrs))
  end

  # Unsaved, so the validation tests can inspect errors instead of tripping
  # create!'s exception.
  def build_target(priority, attrs: {})
    WindowsTarget.new({
      address: "host-#{SecureRandom.hex(4)}.example.com",
      polling_priority: priority,
      event_logs: 'Application',
    }.merge(attrs))
  end

  # ---- the seeded bands --------------------------------------------------

  test 'the three priority levels ship with the documented intervals' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    p2 = PollingPriority.find_by(name: 'Priority 2')
    p3 = PollingPriority.find_by(name: 'Priority 3')

    assert p1 && p2 && p3, 'the migration must seed all three levels'
    assert_equal 300,   p1.max_interval_secs, 'Priority 1: at least every 5 minutes'
    assert_equal 1_800,  p2.max_interval_secs, 'Priority 2: at least every 30 minutes'
    assert_equal 21_600, p3.max_interval_secs, 'Priority 3: at least every 6 hours'
  end

  test 'a new priority level is a row, not a code change' do
    added = priority('Priority 4', 21_600, 86_400)

    assert added.valid?
    assert_equal 86_400, added.max_interval_secs
    assert_includes PollingPriority.ordered, added
  end

  # ---- the priority floor ------------------------------------------------

  test 'a silent host is still polled at its priority maximum' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    assert_equal 300, target(p1, rate: 0.0).next_interval_secs
  end

  test 'a quiet host on a low priority waits no longer than its priority allows' do
    p3 = PollingPriority.find_by(name: 'Priority 3')

    assert_equal 21_600, target(p3, rate: 0.001).next_interval_secs
  end

  test 'a busy host is polled sooner than a quiet one on the same priority' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    quiet = target(p1, rate: 0.1)
    busy  = target(p1, rate: 200.0)

    assert_equal 300, quiet.next_interval_secs
    assert_equal 60,  busy.next_interval_secs, 'clamped to the band floor, not below it'
    assert_operator busy.next_interval_secs, :<, quiet.next_interval_secs
  end

  test 'the interval never falls below the priority minimum' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    assert_equal 60, target(p1, rate: 100_000.0).next_interval_secs
  end

  test 'the interval never exceeds the priority maximum' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    assert_equal 300, target(p1, rate: 1e-9).next_interval_secs
  end

  # 500.0 / 0.0 is Infinity, and Infinity.round raises FloatDomainError. A
  # brand-new target starts at rate 0, so this is the first call the poller makes.
  test 'a zero rate does not raise' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    assert_equal 300, target(p1, rate: 0.0).next_interval_secs
  end

  # ---- the deadband ------------------------------------------------------

  test 'a small change in rate does not move the interval' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1, rate: 5.0)
    host.update!(last_polled_at: Time.now - 100, next_poll_at: Time.now)

    before = host.current_interval_secs
    host.events_per_second = 5.4
    assert_equal before, host.next_interval_secs
  end

  test 'a large change in rate does move the interval' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1, rate: 0.5)
    host.update!(last_polled_at: Time.now - 300, next_poll_at: Time.now)

    assert_equal 300, host.current_interval_secs
    host.events_per_second = 50.0
    assert_operator host.next_interval_secs, :<, 300
  end

  # ---- recording a poll --------------------------------------------------

  test 'record_poll! advances next_poll_at so the host is not polled twice' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1)
    assert_nil host.next_poll_at

    host.record_poll!(event_count: 0, status: 'ok')

    assert_not_nil host.next_poll_at
    assert_operator host.next_poll_at, :>, Time.now
    refute host.due?
  end

  test 'a busy host gets polled sooner on the next pass' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1)

    host.record_poll!(event_count: 0, status: 'ok')
    quiet_gap = host.next_poll_at - host.last_polled_at

    # A burst of events on the next poll should shorten the following gap.
    host.record_poll!(event_count: 4_000, status: 'ok')
    busy_gap = host.next_poll_at - host.last_polled_at

    assert_operator busy_gap, :<, quiet_gap
  end

  test 'the rate is smoothed so one burst does not pin the interval' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1)

    host.record_poll!(event_count: 10_000, status: 'ok')
    spiked = host.events_per_second

    host.record_poll!(event_count: 0, status: 'ok')
    decayed = host.events_per_second

    assert_operator decayed, :<, spiked, 'the spike decays'
    assert_operator decayed, :>, 0.0, 'and does not snap straight back to zero'
  end

  test 'a failed poll still advances the schedule' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1)

    host.record_poll!(event_count: 0, status: 'partial: Application: RuntimeError')

    assert_match(/partial/, host.last_status)
    assert_operator host.next_poll_at, :>, Time.now
  end

  # ---- due / enabled -----------------------------------------------------

  test 'a never-polled target is due immediately' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    assert target(p1).due?
    assert_includes WindowsTarget.due, target(p1)
  end

  test 'a disabled target is never due' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1)
    host.disable!

    refute host.due?
    refute_includes WindowsTarget.due, host
    assert_nil host.next_poll_at
  end

  test 'disabling keeps the measured rate and credentials' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1, attrs: { username: 'svc-poll', password: 'hunter2' })
    host.record_poll!(event_count: 500, status: 'ok')
    rate = host.events_per_second

    host.disable!
    host.reload

    assert_equal rate, host.events_per_second
    assert_equal 'svc-poll', host.username
    assert_equal 'hunter2', host.password, 'the credential survives a disable'
  end

  # rank is the ordering key, so a lower rank goes first when a cycle cannot
  # poll everything.
  test 'due orders by priority rank so critical hosts go first' do
    base = PollingPriority.maximum(:rank).to_i
    critical = priority('Critical', 60, 300, rank: base + 10)
    bulk     = priority('Bulk', 600, 7_200, rank: base + 11)
    high = target(critical)
    low  = target(bulk)

    assert_equal [high.id, low.id], WindowsTarget.due.pluck(:id)
  end

  # ---- validation --------------------------------------------------------

  test 'a channel name is required' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    refute build_target(p1, attrs: { event_logs: '' }).valid?
    refute build_target(p1, attrs: { event_logs: ' , , ' }).valid?
  end

  # Channel names are interpolated into a wevtutil command line executed on the
  # remote host, so this is the boundary that keeps that command inert.
  test 'a channel name that would break out of the command line is rejected' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    ['Application"; calc.exe', 'Application && whoami', 'Application|more',
     'Application > /tmp/x', '$(id)', 'Application`id`', 'App\nSystem&dir'].each do |bad|
      host = build_target(p1, attrs: { event_logs: bad })
      refute host.valid?, "expected #{bad.inspect} to be rejected"
      assert_match(/event log channels/, host.errors[:event_logs].join)
    end
  end

  test 'real channel names are accepted' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1, attrs: {
      event_logs: 'Application,System,Setup,ForwardedEvents,Microsoft-Windows-PowerShell/Operational' })

    assert host.valid?, host.errors.full_messages.join
    assert_equal 5, host.log_list.size
  end

  test 'an address that would alter the WinRM endpoint is rejected' do
    p1 = PollingPriority.find_by(name: 'Priority 1')

    ['http://evil/x', 'host:80/wsman', 'host /x', 'host;id', 'host`id`', ''].each do |bad|
      refute build_target(p1, attrs: { address: bad }).valid?, "expected #{bad.inspect} to be rejected"
    end
  end

  test 'an address must be unique' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    first = target(p1, attrs: { address: 'dup.example.com' })

    dup = WindowsTarget.new(address: 'dup.example.com', polling_priority: p1, event_logs: 'System')
    refute dup.valid?
    assert first.valid?
  end

  # ---- credentials at rest -----------------------------------------------

  test 'the password is not stored in the clear' do
    p1 = PollingPriority.find_by(name: 'Priority 1')
    host = target(p1, attrs: { username: 'svc-poll', password: 'hunter2' })
    host.save!

    raw = WindowsTarget.connection.select_value(
      "select password from windows_targets where id = #{host.id}")

    assert_not_nil raw, 'the encrypted column must actually be written'
    refute_includes raw, 'hunter2', 'the column must not hold the credential in the clear'
    assert_equal 'hunter2', WindowsTarget.find(host.id).password
  end

  # The column is named `password` and holds ciphertext. Asserting the raw value
  # differs from the credential is what pins that; a column named
  # password_ciphertext would instead leave the encrypted attribute with no
  # backing column, and saves would silently write nothing.
  test 'the password column is text, so a ciphertext payload fits' do
    assert_includes WindowsTarget.column_names, 'password'

    type = WindowsTarget.columns_hash['password'].sql_type
    assert_equal 'text', type
  end
end
