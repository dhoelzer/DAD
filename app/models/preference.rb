# Application-level settings.
#
# Only one row is meaningfully used: user_id 0, the shared/global preference row
# that stores how many live events the dashboard requests per poll.
class Preference < ActiveRecord::Base
  # Show the "Preferences" tab only to users holding the Viewer right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end

  # Clamped on write, not just in #archiveFreeSpacePercent below: the value also
  # arrives through the Preferences form, which calls the plain attribute setter.
  # An unclamped 1000 would be read back as "keep 1000% of the partition free",
  # a requirement no filesystem can meet, and pruning would then delete every
  # archive on disk.
  #
  # Blank means "no floor" (NULL) rather than 0, so the Preferences screen can
  # tell an operator the setting was never made rather than that they chose zero.
  def archiveFreeSpacePercent=(value)
    if value.nil? || (value.respond_to?(:strip) && value.strip.empty?)
      super(nil)
      return
    end
    clamped = value.to_i
    clamped = clamped.clamp(0, 100)
    super(clamped)
  end

  # Starting feed size when the setting has never been made. Matches the value
  # Event seeds its in-process counter with, and the target Event.recent_events
  # converges on.
  DEFAULT_EVENTS_DASHBOARD = 50

  # The global row, or nil. Read-only: callers on the GET path must not create
  # rows (see Event.recent_events), so they take the default instead.
  def self.global_row
    find_by(user_id: 0)
  end

  # The global row, created if absent. Only for write paths: the row is not
  # seeded by any migration, so the first writer has to be able to make it.
  def self.global_row!
    global_row || create!(user_id: 0)
  end

  # Reads (or, with an argument, writes) the dashboard's live event count.
  #
  # Called by Event.recent_events to size its query, and by that method again to
  # persist an adjusted value. With numDisplayed == -1 it returns the current
  # setting; otherwise it saves the new value.
  #
  # The read never writes and never returns nil. Nothing migrates the user_id 0
  # row into existence, and recent_events runs on GET /events.js, where creating
  # a row would be a side effect a proxy may replay -- so an unset setting yields
  # DEFAULT_EVENTS_DASHBOARD. Returning nil there raised NoMethodError and 500s
  # the whole dashboard poll, which is what left #graphs and #events_window
  # permanently empty.
  #
  # NULL and 0 both fall back. recent_events sizes its query with to_i, so NULL
  # arrived as 0, and 0 is not a usable page size: the feed is clamped to a
  # minimum of 1 row, and the self-tuning grows by `configured * 0.10`, which is
  # 0 when configured is 0. A stored 0 therefore pinned the dashboard at a single
  # event with no way back. Note `0 || default` is 0 in Ruby -- zero is truthy --
  # so the guard has to be numeric, not a bare ||.
  def self.eventsDashboard(numDisplayed = -1)
    if numDisplayed == -1
      stored = global_row&.liveEventsDisplayed
      return DEFAULT_EVENTS_DASHBOARD if stored.nil? || stored.to_i <= 0
      return stored.to_i
    end
    pref = global_row!
    pref.liveEventsDisplayed = numDisplayed
    pref.save
  end

  # Percentage of the archive partition that must stay free (0-100).
  #
  # Read by EventPartitionBackup.prune_archives: whenever the archives plus what
  # the next archive needs would push the partition past 100 - this, the oldest
  # archives are deleted until it fits. nil or 0 means no floor, and pruning is
  # off -- the default, because pruning deletes the only copy of a month's rows.
  #
  # Called with an argument to write, without one to read. nil writes "no floor".
  #
  # The read returns nil when the setting has never been made, which is the
  # documented "no floor" value. The write creates the row: before it did not,
  # `Preference.where(...).first` was nil, the method returned nil, and saving
  # the Preferences form reported success while discarding the floor the
  # operator had just set.
  def self.archiveFreeSpacePercent(percent = :unset)
    return global_row&.archiveFreeSpacePercent if percent == :unset
    pref = global_row!
    pref.archiveFreeSpacePercent = percent
    pref.save
    pref.archiveFreeSpacePercent
  end
end
