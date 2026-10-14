# Admin CRUD over the Session table (active logins), plus the means to revoke one.
#
# Ordinary login/logout does not go through here: Sessions are created by
# UsersController#do_logon and consumed by ApplicationController#gatekeeper. These
# actions exist so an administrator can inspect and force-terminate sessions.
class SessionsController < ApplicationController
  before_action :set_session, only: [:show, :edit, :update, :destroy]

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
    # Internal: runs as a before_action for show/edit/update/destroy.
    def set_session
      @session = Session.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    # Attribute whitelist for session writes.
    #
    # BUG: permits :hash, but the Session column is session_hash, so #create and
    # #update raise ActiveRecord::UnknownAttributeError rather than ignoring the
    # key. The admin session create/edit forms are therefore broken; only index,
    # show and destroy work. See RECOMMENDATIONS.md 5.5.
    def session_params
      params.require(:session).permit(:hash, :user_id, :expiry)
    end
end
