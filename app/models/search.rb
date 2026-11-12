# A saved search: a search string, kept for re-running. No time window is
# stored -- the timeframe is chosen again at run time.
#
# Purely a stored bookmark. SearchesController persists the record and the
# events search form can re-populate itself from it; the actual query is still
# executed by Event.search.
class Search < ActiveRecord::Base
  # Show the "Searches" tab only to users holding the Detective right.
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Detective")
    return false
  end
end
