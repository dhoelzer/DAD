# Read-only inspection of the Session table (active logins), plus the means to
# revoke one. create/new/edit/update are deliberately not routed: minting a
# session row by hand would bypass the password check entirely.
#
# Ordinary login/logout does not go through here: Sessions are created by
# UsersController#do_logon and consumed by ApplicationController#gatekeeper. These
# actions exist so an administrator can inspect and force-terminate sessions.
class SessionsController < ApplicationController
  before_action :set_session, only: [:show, :destroy]

  # GET /sessions (and .json) -- every session row, i.e. who is logged in and when
  # each session expires. No pagination.
  def index
    @sessions = Session.all
  end

  # GET /sessions/1 (and .json) -- one session row.
  def show
  end

  # DELETE /sessions/1 (and .json) -- force-terminates a login.
  def destroy
    @session.destroy
    respond_to do |format|
      format.html { redirect_to sessions_url, notice: 'Session was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    # Loads @session from params[:id]; raises 404 when there is no such record.
    # Internal: runs as a before_action for show/destroy.
    def set_session
      @session = Session.find(params[:id])
    end
end
