# Base controller: enforces HTTPS, resolves the session cookie into @current_user,
# and gates every action behind an authorisation check.
#
# Every other controller inherits from this. The three before_filters run in order
# for all actions: #ssl, #gatekeeper, #authorized?. A subclass customises access by
# defining its own #authorized?, which replaces the one below for that controller
# only.
class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_filter :ssl, :gatekeeper, :authorized?

  # Redirects plain-HTTP requests to the equivalent HTTPS URL. Skipped in development
  # so the dev server can be used over http. Returns false after redirecting, which
  # halts the filter chain. Internal: runs as a before_filter.
  def ssl
    return true if Rails.env == "development" # Do not redirect to SSL in development.
    if request.protocol == "http://" then
      url = "https://" + request.original_url[7..-1]
      redirect_to url
      return false
    end
    return true
  end

  # Resolves the :sessionID cookie into @current_user and slides the session's expiry
  # forward an hour on each request, so an active session never times out in use.
  #
  # Leaves @current_user nil when there is no cookie, the token is unknown, or the
  # session has expired (expired rows are deleted here). Internal: runs as a
  # before_filter, and both #authorized? and the views depend on @current_user having
  # been set by this first. The cookie is HttpOnly, and Secure except in development.
  def gatekeeper
    @current_user = nil
    if cookies[:sessionID] then
      @session = Session.find_by_session_hash(cookies[:sessionID])
      if !@session.nil? then
        if @session.expiry < Time.now then
          @session.destroy
          @session.save
          @session = nil
        end
      end
      @current_user = User.find(@session.user_id) unless @session.nil?
      if(@session) then
        set_session_cookie(@session.session_hash)
        @session.expiry = Time.now + 1.hour
        @session.save
      end
    end
  end

  # Writes the :sessionID cookie with a consistent set of hardening options.
  #
  # Shared by #gatekeeper (sliding the expiry forward on each request) and
  # UsersController#do_logon (issuing it at login), so the two cannot drift apart.
  # HttpOnly keeps it out of JavaScript; Secure is off only in development so the
  # dev server works over http; SameSite=Lax blocks cross-site POSTs from
  # carrying the token.
  def set_session_cookie(token)
    cookies[:sessionID] = {
      value: token,
      httponly: true,
      secure: (Rails.env != "development"),
      same_site: :lax,
      expires: Time.now + 1.hour
    }
  end

  # Default gate: requires any logged-in user, redirecting to the logon page
  # otherwise. Unless a controller defines its own authorized?, this is what runs.
  # Subclasses override it to require a specific right (Viewer, Commentator,
  # Detective, Taskmaster, Admin).
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true
  end


end
