# A logged-in session: an opaque cookie token bound to a User with an expiry.
#
# Rows are created by UsersController#do_logon and looked up on every request by
# ApplicationController#gatekeeper via the :sessionID cookie. The token is
# regenerated on each successful logon and all of a user's sessions are dropped
# at once, so logging in elsewhere signs previous sessions out.
class Session < ActiveRecord::Base
  belongs_to :user

  # session_hash is the sole bearer credential gatekeeper accepts, so two rows
  # sharing one token would mean two users sharing a login.
  validates :session_hash, presence: true, uniqueness: true
  validates :expiry, presence: true

  # Reclaims rows whose expiry has passed.
  #
  # gatekeeper deletes an expired row only when the cookie owning it comes back,
  # so an operator who logs in and closes the tab leaves the row forever. The
  # table is scanned by the per-request cookie lookup, so those rows are not
  # just untidy -- they make every request slower.
  #
  # Returns the number of rows removed.
  def self.purge_expired
    where('expiry < ?', Time.now).delete_all
  end

  # Sessions are managed implicitly by logon/logoff; the admin CRUD screen is
  # reachable by URL but the tab is hidden from the navigation bar.
  def self.hidden?(current_user = nil)
    return true
  end
end
