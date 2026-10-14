# Base controller: enforces HTTPS, resolves the session cookie into @current_user,
# and gates every action behind an authorisation check.
#
# Every other controller inherits from this. The three before_filters run in order
# for all actions: #ssl, #gatekeeper, #authorized?. Access control is declared in
# the constants below rather than by overriding #authorized? per controller, so the
# whole policy is readable in one place.
class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  # Rights that satisfy each controller, any one of them. User#has_right? already
  # returns true for an Admin regardless of the right asked for, so Admin needs no
  # entry here. A controller missing from this map is DENIED, not allowed -- see
  # #authorized?.
  CONTROLLER_RIGHTS = {
    'alerts'      => %w[Viewer Commentator],
    'comments'    => %w[Commentator],
    'displays'    => %w[Detective],
    'events'      => %w[Viewer],
    'exclusions'  => %w[Commentator],
    'hunks'       => %w[Admin],
    'jobs'        => %w[Taskmaster],
    'preferences' => %w[Admin],
    'rights'      => %w[Admin],
    'roles'       => %w[Admin],
    'searches'    => %w[Viewer],
    'services'    => %w[Admin],
    'sessions'    => %w[Admin],
    'statistics'  => %w[Admin],
    'systems'     => %w[Viewer],
    'users'       => %w[Admin],
    'words'       => %w[Admin]
  }.freeze

  # Actions whose requirement is stricter than their controller's default.
  # Saving a search is a Detective action; reading one is a Viewer action.
  ACTION_RIGHTS = {
    'searches' => {
      'new'     => %w[Detective],
      'edit'    => %w[Detective],
      'create'  => %w[Detective],
      'update'  => %w[Detective],
      'destroy' => %w[Detective]
    }
  }.freeze

  # Actions reachable with no session at all. Without this the login form itself
  # would sit behind the login check.
  PUBLIC_ACTIONS = { 'users' => %w[logon do_logon logoff] }.freeze

  before_filter :ssl, :gatekeeper, :authorized?

  # The rights that grant +controller+#+action+, or nil when nothing grants it.
  # Public actions are handled by #authorized? before this is consulted, so nil
  # here means "denied" with no second meaning. Class method so the policy is
  # testable without instantiating a request.
  def self.required_rights(controller, action)
    override = ACTION_RIGHTS[controller]
    return override[action] if override && override.key?(action)
    CONTROLLER_RIGHTS[controller]
  end

  # Everything below is request plumbing, not actions. ActionController::Base
  # treats every public method as a candidate action (see #action_methods), so
  # leaving the filters public advertised #ssl, #gatekeeper, #set_session_cookie
  # and #authorized? as actions on every controller. They are reached only as
  # filters or, for #set_session_cookie, from UsersController with an implicit
  # receiver, so private is safe and removes them from action_methods.
  private

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

  # The single access-control gate. Private so it is not a routable action:
  # ActionController::Base.action_methods treats every public method as an action,
  # and a public #authorized? was reachable as GET /users/authorized.
  #
  # Denies by default. A controller absent from CONTROLLER_RIGHTS is unreachable
  # rather than open, so adding a controller without declaring its rights fails
  # closed instead of exposing it.
  def authorized?
    controller = params[:controller]
    action = params[:action]

    return true if PUBLIC_ACTIONS[controller] && PUBLIC_ACTIONS[controller].include?(action)

    if @current_user.nil?
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end

    required = self.class.required_rights(controller, action)
    if required && required.any? { |right| @current_user.has_right?(right) }
      return true
    end

    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

end
