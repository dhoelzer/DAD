# A logged-in session: an opaque cookie token bound to a User with an expiry.
#
# Rows are created by UsersController#do_logon and looked up on every request by
# ApplicationController#gatekeeper via the :sessionID cookie. The token is
# regenerated on each successful logon and all of a user's sessions are dropped
# at once, so logging in elsewhere signs previous sessions out.
class Session < ActiveRecord::Base
  belongs_to :user

  # Sessions are managed implicitly by logon/logoff; the admin CRUD screen is
  # reachable by URL but the tab is hidden from the navigation bar.
  def self.hidden?(current_user = nil)
    return true
  end
end
