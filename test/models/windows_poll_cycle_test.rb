require 'test_helper'
require_relative '../../lib/windows_poll_cycle'

# The scheduling half of the feature: which hosts get polled in a pass, and what
# happens when one of them fails.
#
# The transport is faked. There is no Windows host in CI, and the behaviour under
# test is the due-list selection and the per-target isolation, not the wire.
class WindowsPollCycleTest < ActiveSupport::TestCase
  # Stands in for WindowsPoll. Records what it was asked to poll so the tests can
  # assert on selection rather than on side effects, and can fail one named host
  # while succeeding on the rest.
  class FakePoller
    attr_reader :calls
    attr_accessor :events, :raise_for

    def initialize(events: 0, raise_for: nil)
      @calls = []
      @events = events
      @raise_for = raise_for
    end

    def poll(target, transport: nil)
      calls << target.address
      raise Errno::ECONNREFUSED if raise_for == target.address
      WindowsPoll::Result.new(event_count: events, status: 'ok', detail: nil)
    end
  end

  setup do
    WindowsTarget.delete_all
    PollingPriority.where.not(name: ['Priority 1', 'Priority 2', 'Priority 3']).delete_all
  end

  def priority(name, min_secs, max_secs, rank: PollingPriority.maximum(:rank).to_i + 1)
    PollingPriority.create!(name: name, rank: rank,
                            min_interval_secs: min_secs, max_interval_secs: max_secs)
  end

  def target(priority, address: "h#{SecureRandom.hex(4)}.example.com", enabled: true, next_poll_at: nil)
    WindowsTarget.create!(address: address, polling_priority: priority,
                          event_logs: 'Application', enabled: enabled,
                          next_poll_at: next_poll_at)
  end

  test 'polls every enabled target that is due' do
    p1 = priority('Due1', 60, 300)
    a = target(p1)
    b = target(p1)

    poller = FakePoller.new
    result = WindowsPollCycle.run(poller: poller)

    assert_equal 2, result[:polled]
    assert_equal [a.address, b.address].sort, poller.calls.sort
    assert_empty result[:failed]
  end

  test 'skips a target that is not due yet' do
    p1 = priority('Skip1', 60, 300)
    due = target(p1)
    later = target(p1, next_poll_at: Time.now + 3_600)

    poller = FakePoller.new
    result = WindowsPollCycle.run(poller: poller)

    assert_equal [due.address], poller.calls
    assert_equal 1, result[:polled]
    refute_includes poller.calls, later.address
  end

  test 'skips a disabled target' do
    p1 = priority('Off1', 60, 300)
    on = target(p1)
    off = target(p1, enabled: false)

    poller = FakePoller.new
    WindowsPollCycle.run(poller: poller)

    assert_equal [on.address], poller.calls
    refute_includes poller.calls, off.address
  end

  # The point of the whole feature: a host that produced a lot of events is
  # scheduled sooner than one that produced none.
  test 'a busy host ends up scheduled sooner than a quiet one' do
    p1 = priority('Adapt', 60, 300)
    busy  = target(p1, address: 'busy.example.com')
    quiet = target(p1, address: 'quiet.example.com')

    # Per-host event counts, so the two hosts differ only in how busy they are.
    per_host = Class.new do
      def poll(target, transport: nil)
        count = target.address == 'busy.example.com' ? 4_000 : 0
        WindowsPoll::Result.new(event_count: count, status: 'ok', detail: nil)
      end
    end.new
    WindowsPollCycle.run(poller: per_host)

    busy_gap  = busy.reload.next_poll_at - busy.last_polled_at
    quiet_gap = quiet.reload.next_poll_at - quiet.last_polled_at

    assert_operator busy_gap, :<, quiet_gap
  end

  # A host that is down, firewalled or miscredentialed is a normal condition in a
  # fleet. It must not take the cycle, or the other hosts, down with it.
  test 'a target that raises does not stop the others' do
    p1 = priority('Iso1', 60, 300)
    good = target(p1, address: 'good.example.com')
    target(p1, address: 'broken.example.com')

    poller = FakePoller.new(raise_for: 'broken.example.com')
    result = WindowsPollCycle.run(poller: poller)

    assert_equal ['broken.example.com'], result[:failed]
    assert_equal ['broken.example.com', 'good.example.com'].sort, poller.calls.sort
    assert good.reload.enabled?, 'a failing peer must not disable a healthy host'
  end

  test 'a target that raises is still rescheduled so it is not retried every cycle' do
    p1 = priority('Iso2', 60, 300)
    host = target(p1, address: 'down.example.com')

    WindowsPollCycle.run(poller: FakePoller.new(raise_for: 'down.example.com'))

    host.reload
    assert_not_nil host.next_poll_at, 'otherwise it is due again on the very next cycle'
    assert_operator host.next_poll_at, :>, Time.now
    assert_match(/ECONNREFUSED/, host.last_status)
  end

  test 'the summary counts events across targets' do
    p1 = priority('Count', 60, 300)
    3.times { target(p1) }

    result = WindowsPollCycle.run(poller: FakePoller.new(events: 7))

    assert_equal 3, result[:polled]
    assert_equal 21, result[:events]
  end

  # The JobHandler entry point must exist and be name-addressable, since a Job
  # row can only name a registered handler.
  test 'the poller is registered as a Job handler' do
    assert JobHandler.known?('poll_windows_events')
    assert_includes JobHandler.names, 'poll_windows_events'
  end
end
