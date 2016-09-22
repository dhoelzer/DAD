class Preference < ActiveRecord::Base
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end

  def self.eventsDashboard
  	Preference.where(:user_id => 0).first.liveEventsDisplayed
  end
  def self.eventsDashboard(numDisplayed)
  	pref = Preference.where(:user_id => 0).first
  	pref.liveEventsDisplayed = numDisplayed
  	pref.save
  end
end
