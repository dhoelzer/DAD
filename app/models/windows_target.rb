# A Windows host DAD polls for event-log records over WinRM.
#
# This is a pull model: DAD connects to the host and asks for the records. That
# is the opposite of the OpenWEC path, which receives events pushed by hosts
# configured in Group Policy. Pulling removes the external collector and, more
# importantly for this feature, puts the polling cadence under DAD's control --
# under push there is no interval to tune at all.
#
# The row carries the scheduler's memory. The poller runs under Restart=always,
# so measured rate and next_poll_at live here rather than in process memory: a
# crash between polls must not send a busy host back to its slowest interval,
# and must not re-poll a host that was just polled.
class WindowsTarget < ActiveRecord::Base
  belongs_to :polling_priority

  # Hidden from the nav bar only for users without the Viewer right; the tab is
  # the operator's list of monitored Windows hosts.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?('Viewer')
    false
  end

  # Channel names are interpolated into a wevtutil command line that is executed
  # on the remote host. Anything outside this set is rejected rather than
  # escaped, because the command is built for cmd.exe on Windows and shell
  # quoting rules there are not the ones Ruby's escaping assumes.
  #
  # Real channel names fit: Application, System, Setup, ForwardedEvents, and
  # provider channels like "Microsoft-Windows-PowerShell/Operational".
  LOG_NAME = /\A[A-Za-z0-9][A-Za-z0-9._\-\/]*\z/.freeze

  # A host address is used to build the WinRM endpoint URL. Restricting it keeps
  # a crafted address from pointing the poller at some other scheme or host.
  ADDRESS = /\A[A-Za-z0-9][A-Za-z0-9.\-_:]*\z/.freeze

  validates :address, presence: true, uniqueness: true, format: { with: ADDRESS }
  validates :event_logs, presence: true
  validate :event_logs_are_safe_channel_names

  # Credentials are encrypted at rest. The `password` column holds ciphertext,
  # not plaintext: Rails' encrypts writes the encrypted payload to the column
  # matching the attribute name. A WinRM password is a domain credential, and in
  # the clear it would sit in every pg_dump, backup and replica.
  encrypts :password

  # Label for this host, matching System#display_name so the two read alike.
  def display_name
    return "(#{address})" if name.nil? || name.strip.empty?
    name
  end

  # The configured channels as an Array, in the order entered.
  def log_list
    event_logs.to_s.split(',').map(&:strip).reject(&:empty?)
  end

  # Enabled targets whose next_poll_at has arrived. A target that has never been
  # polled has next_poll_at NULL and is therefore due immediately.
  #
  # Ordered by rank then id so that when the budget for a cycle is limited, the
  # most critical hosts go first.
  def self.due(now = Time.now)
    enabled.joins(:polling_priority)
           .where('windows_targets.next_poll_at IS NULL OR windows_targets.next_poll_at <= ?', now)
           .order('polling_priorities.rank ASC', 'windows_targets.id ASC')
  end

  def self.enabled
    where(enabled: true)
  end

  # True when this target should be polled now.
  def due?(now = Time.now)
    return false unless enabled?
    next_poll_at.nil? || next_poll_at <= now
  end

  # The interval to wait before the next poll, in seconds.
  #
  # A proportional controller aimed at a bounded number of events per poll:
  #
  #   interval = TARGET_EVENTS_PER_POLL / smoothed_rate
  #
  # A host producing 5000 events/s therefore lands on a 0.1s raw interval and a
  # quiet host on a huge one; clamping into the priority band is what turns that
  # into "more often when busy, never less often than the priority guarantee".
  #
  # Clamping is what makes the priority meaningful. A Priority 1 host that goes
  # completely silent has rate 0, an infinite raw interval, and lands on
  # max_interval_secs -- 300s -- which is exactly the "at least every five
  # minutes" the level promises.
  #
  # The deadband stops jitter. Recomputing from a noisy rate every poll makes the
  # interval oscillate, and an oscillating interval is indistinguishable from a
  # bug when you are trying to reason about when a host was last polled. A change
  # has to be at least 25% off the current interval to be worth acting on.
  TARGET_EVENTS_PER_POLL = 500.0
  DEADBAND = 0.25

  def next_interval_secs
    band_min = polling_priority.min_interval_secs
    band_max = polling_priority.max_interval_secs
    desired = desired_interval_secs(band_min, band_max)

    current = current_interval_secs
    return desired if current.nil?

    # Only move when the change is material.
    return current if (desired - current).abs < current * DEADBAND

    desired
  end

  # A zero rate means "nothing observed", which is the quietest a host can be, so
  # it takes the slowest interval the priority allows. Dividing first would give
  # Infinity, and Infinity.round raises FloatDomainError.
  def desired_interval_secs(band_min, band_max)
    return band_max if events_per_second.nil? || events_per_second <= 0
    (TARGET_EVENTS_PER_POLL / events_per_second).round.clamp(band_min, band_max)
  end

  # The interval actually in force right now, derived from when the last poll
  # happened and when the next one is scheduled. nil until a poll has run.
  def current_interval_secs
    return nil if last_polled_at.nil? || next_poll_at.nil?
    (next_poll_at - last_polled_at).round
  end

  # Records one completed poll and schedules the next.
  #
  # The rate is smoothed rather than replaced. A single burst -- a host rebooting,
  # a logon storm -- would otherwise pin a host at its fastest interval for hours,
  # and then a single quiet window would drop it back. The exponential moving
  # average lets a spike decay over a few polls instead.
  #
  # elapsed is floored at 1s: two polls a fraction apart would otherwise divide
  # by ~0 and report an enormous rate.
  def record_poll!(event_count:, status:, at: Time.now)
    elapsed = last_polled_at.nil? ? 0.0 : (at - last_polled_at)
    elapsed = 1.0 if elapsed < 1.0

    observed = event_count.to_f / elapsed
    alpha = 0.4
    smoothed = poll_count.zero? ? observed : (alpha * observed) + ((1 - alpha) * events_per_second)

    self.events_per_second = smoothed
    self.last_event_count = event_count
    self.poll_count += 1
    self.last_polled_at = at
    self.last_status = status.to_s[0, 255]
    self.next_poll_at = at + next_interval_secs
    save!
  end

  # Stops a target being polled without losing its measured rate or credentials,
  # which is what distinguishes disabling from deleting.
  def disable!
    update!(enabled: false, next_poll_at: nil)
  end

  private

  # Every configured channel must match LOG_NAME. These strings are joined into
  # a wevtutil command line that runs on the remote host, so an unvalidated
  # channel name is remote command execution on a machine DAD is authenticating
  # to with a domain credential.
  def event_logs_are_safe_channel_names
    names = event_logs.to_s.split(',')
    if names.map(&:strip).reject(&:empty?).empty?
      errors.add(:event_logs, 'must name at least one event log')
      return
    end

    bad = names.map(&:strip).reject { |n| n.match?(LOG_NAME) }
    return if bad.empty?

    errors.add(:event_logs,
               "contains names that are not valid event log channels: #{bad.join(', ')}")
  end
end
