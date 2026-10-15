# A saved search: a search string plus its time window, kept for re-running.
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
