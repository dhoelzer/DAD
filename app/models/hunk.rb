# A single whitespace-delimited token harvested from an event line.
#
# Leftover from an earlier normalisation scheme. Events are tokenised into
# `words` through the `events_words` join table (see EventIngestor.storeEvent); nothing
# in the current app reads or writes `hunks` via this model. The table remains in
# the schema and HunkController still exposes CRUD screens for it.
#
# Do not use this class for new work -- use Word.
class Hunk < ActiveRecord::Base
  # Never exposed in the navigation bar. The layout calls
  # `model.constantize.hidden?(@current_user)` for every entry in $_models;
  # returning true unconditionally keeps the "Hunks" tab hidden for all users.
  def self.hidden?(current_user = nil)
    return true
  end
end
