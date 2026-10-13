# A regex pattern whose matching events are filtered out of the live dashboard.
#
# Exclusions are applied in Event.recent_events, which plucks every pattern and
# rejects any event line matching the union of them. They do not affect stored
# data or search results -- only what the dashboard displays.
class Exclusion < ActiveRecord::Base
  belongs_to :user

  # Show the "Exclusions" tab only to users holding the Commentator right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Commentator")
    return false
  end
end
