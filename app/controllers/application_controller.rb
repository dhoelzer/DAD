class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  
  before_filter :ssl, :gatekeeper, :authorized?
    
  def ssl
    return true if Rails.env == "development" # Do not redirect to SSL in development.
    if request.protocol == "http://" then
      url = "https://" + request.original_url[7..-1]
      redirect_to url
      return false
    end
    return true
  end
  
  def gatekeeper
    @current_user = nil
    if cookies[:sessionID] then
      @session = Session.find_by_session_hash(cookies[:sessionID])
      @session = nil if !@session.nil? && @session.expiry < Time.now
      @current_user = User.find(@session.user_id) unless @session.nil?
      if(@session) then
        if Rails.env == "development" then
          cookies[:sessionID] = { value: @session.session_hash, httponly: true, secure: false, expires: Time.now+1.hour }
        else
          cookies[:sessionID] = { value: @session.session_hash, httponly: true, secure: true, expires: Time.now+1.hour }
        end
        @session.expiry = Time.now + 1.hour
        @session.save
      end
    end
  end
  
  # Unless there is a local Authorized? function in the controller, this will be called.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true
  end
  
end
