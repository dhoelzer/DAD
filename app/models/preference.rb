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
end
