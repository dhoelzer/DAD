require 'windows_poll'

# One pass of the Windows poller: poll every target that is due, skip the rest.
#
# Extracted from the JobHandler entry the way JobScheduler is extracted from
# scheduler.rb, so the scheduling decisions can be tested without a Windows host
# or a WinRM connection.
#
# The invariant this protects: no single host can stop any other host from being
# polled, and none can take the scheduler down. A host that is down, miscredentialed
# or firewalled is a normal condition in a fleet, not an exception.
class WindowsPollCycle
  # Per-target failures are captured in the Result, but a failure in the
  # bookkeeping around it (record_poll!, a dead connection object) can still
  # raise. Caught here so one bad row cannot end the cycle.
  def self.run(now: Time.now, poller: WindowsPoll, transport_factory: nil)
    due = WindowsTarget.due(now)
    polled = 0
    events = 0
    failed = []

    due.each do |target|
      begin
        result = poll_one(target, poller, transport_factory)
        polled += 1
        events += result.event_count
        failed << target.address unless result.status == 'ok'
      rescue StandardError => e
        # Still advance the schedule, or a target that fails here is selected as
        # due on every cycle forever and burns a connection attempt each time.
        target.update!(last_status: "#{e.class}: #{e.message}"[0, 255],
                       next_poll_at: now + target.polling_priority.max_interval_secs)
        failed << target.address
      end
    end

    { polled: polled, events: events, failed: failed }
  end

  def self.poll_one(target, poller, transport_factory)
    transport = transport_factory&.call(target)
    result = poller.poll(target, transport: transport)
    # record_poll! is what advances next_poll_at, and it recomputes the interval
    # from the rate just observed. That is the feedback loop: this call is the
    # only thing that makes a busy host get polled sooner.
    target.record_poll!(event_count: result.event_count, status: result.status, at: Time.now)
    result
  end
end
