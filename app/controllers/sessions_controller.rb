# Admin CRUD over the Session table (active logins), plus the means to revoke one.
#
# Ordinary login/logout does not go through here: Sessions are created by
# UsersController#do_logon and consumed by ApplicationController#gatekeeper. These
# actions exist so an administrator can inspect and force-terminate sessions.
class SessionsController < ApplicationController
  before_action :set_session, only: [:show, :edit, :update, :destroy]

  # DEAD CODE: this file defines authorized? twice and Ruby keeps the last
  # definition, so the copy below is the one that actually runs.
  # Requires the Admin right, redirecting to logon_users_path.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Admin"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # Requires the Admin right; replaces the ApplicationController default.
  # Redirects to /homes when the user lacks it. This is the definition that
  # takes effect, because Ruby keeps the last method definition in a class.
  # Note it looks the right up as a Right *record*, whereas User#has_right?
  # expects a name -- passing a record works only because the lookup below
  # returns nil for it and the Admin short-circuit still applies.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to "/homes"
      return false
    end
    return true if(@current_user.has_right?(Right.find_by_name("Admin")))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to "/homes"
    return false
  end

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
