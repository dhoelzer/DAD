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

  # Reads (or, with an argument, writes) the dashboard's live event count.
  #
  # Called by Event.recent_events to size its query, and by Event.recent_events
  # again to persist an adjusted value. With numDisplayed == -1 it returns the
  # current setting; otherwise it saves the new value. Assumes the global
  # user_id 0 row exists -- it does in a seeded database, and nil otherwise.
  def self.eventsDashboard(numDisplayed=-1)
        return Preference.where(:user_id => 0).first.liveEventsDisplayed if numDisplayed == -1
        pref = Preference.where(:user_id => 0).first
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
  def self.archiveFreeSpacePercent(percent = :unset)
    pref = Preference.where(:user_id => 0).first
    return nil if pref.nil?
    return pref.archiveFreeSpacePercent if percent == :unset
    pref.archiveFreeSpacePercent = percent
    pref.save
    pref.archiveFreeSpacePercent
  end
end
