# Account administration plus the login/logout flow.
#
# This is the only place credentials are checked and the only place a Session is
# issued, so it is the entry point for the whole application.
class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]

  # GET /users (and .json) -- every account.
  def index
    @users = User.all
  end

  # GET /users/1 (and .json) -- one account.
  def show
  end

  # GET /users/:id/roles -- the grant/revoke screen for a user's roles, listing
  # @user.roles plus #ungranted_roles as candidates.
  def roles
    @user = User.find(params[:id])
    @roles = @user.roles
  end

  # Add a role to a user
  # Grants a role (params[:role]) to the user unless they already hold it, then
  # redirects back to #roles. Adding an Admin role is how privilege is escalated, so
  # this action is itself Admin-gated.
  def role_add
    @user = User.find(params[:id])
    @role = Role.find(params[:role])

    if not @user.has_role?(@role)
      @user.roles << @role
      flash[:notice] = "Role successfully added to user."
    else
      flash[:notice] = "That user already has that role!"
    end
    redirect_to :action => :roles, :id => @user
  end

  # Remove a role from a user
  # Revokes a role (params[:role]) from the user if they hold it, then redirects back
  # to #roles.
  def role_remove
    @user = User.find(params[:id])
    @role = Role.find(params[:role])

    if @user.has_role?(@role)
      @user.roles = @user.roles - [@role]
      flash[:notice] = "Role successfully removed from user."
    else
      flash[:notice] = "That user doesn't have that role!"
    end
    redirect_to :action => :roles, :id => @user
  end


  # POST /users/do_logon -- the login form handler.
  #
  # Looks up the username, enforces lockout after 4 failed attempts (resetting the
  # counter once 5 minutes have passed), and on success clears the user's existing
  # sessions, mints a fresh 64-character token, and sets the :sessionID cookie.
  # Redirects to "/" in every case, so a failed login is distinguished only by a
  # flash message. Note a nonexistent username and a wrong password produce different
  # responses, which lets an attacker enumerate accounts.
  def do_logon
    @username = params[:user][:username]
    @password = params[:user][:password]
    @user = User.find_by_username(@username)
    if(@user.nil?) then
      redirect_to "/"
      return false
    end
    if(@user && @user.last_attempt && @user.last_attempt < Time.now - 300) then
      #Reset attempts after 5 minutes
      @user.attempts = 0
      @user.save
    end
    if(@user && @user.attempts > 3) then
      flash[:notice] = "Account Locked!"
      redirect_to "/"
      return false
    end
    if (@user.check_password(@password)) then
      @user.attempts = 0
      @user.save
      Session.where(:user_id => @user.id).each { |session| session.destroy }
      @session = Session.new()
      @session.user_id = @user.id
      @session.expiry = Time.now + 1.hour
      @session.session_hash = generate_session_id
      while Session.find_by_session_hash(@session.session_hash) do
        @session.session_hash = generate_session_id
      end
      @session.user = @user
      @session.save
      set_session_cookie(@session.session_hash)
    else
      flash[:notice] = "Logon Failed!"
      if (@user) then
        @user.attempts = 0 unless @user.attempts
        @user.attempts += 1
        @user.last_attempt = Time.now
        @user.save
        flash[:notice] = "Account Locked!" if(@user.attempts > 3)
        redirect_to "/"
        return false
      end 
    end
    redirect_to "/"
    return true
  end

  # Destroys the current user's session row and clears the cookie. Exempt from the
  # authorization filter so a signed-in user can always sign out.
  def logoff
    if !@current_user.nil? && !@current_user.session.nil?
      session = @current_user.session
      session.destroy!
    end
    cookies.delete(:sessionID)
    @current_user = nil
    redirect_to "/"
  end

  # GET /users/logon -- the sign-in form. Exempt from the authorization filter.
  def logon
    @logon = User.new
  end

  # GET /users/new -- blank registration form (Admin-gated: accounts are created by an
  # administrator, not self-service).
  def new
    @user = User.new
  end

  # GET /users/1/edit -- form for changing an account.
  def edit
  end

  # POST /users (and .json) -- creates an account. The plaintext password from the
  # form is passed through #store_password before saving, so the column never holds a
  # raw password.
  def create
    @user = User.new(user_params)
    @user.attempts = 0
    @user.store_password(@user.password)
    respond_to do |format|
      if @user.save
        format.html { redirect_to @user, notice: 'User was successfully created.' }
        format.json { render :show, status: :created, location: @user }
      else
        format.html { render :new }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /users/1 (and .json) -- updates an account, then re-hashes
  # params[:user][:password] and resets the failed-attempt counter. Because the
  # password is re-hashed unconditionally, an update that omits the password field
  # sets it to a hash of nil.
  def update
    respond_to do |format|
      if @user.update(user_params)
        @user.attempts = 0
        @user.store_password(params[:user][:password])
        @user.save
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1 (and .json) -- deletes an account. Does not revoke that user's
  # existing sessions, so a deleted account stays logged in until its session expires.
  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_to users_url, notice: 'User was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Returns a 64-character alphanumeric token for a session cookie.
  #
  # Internal. Uses rand rather than SecureRandom and indexes the alphabet with
  # rand(10000) %% 62, which is slightly biased toward the earlier characters; see
  # RECOMMENDATIONS.md 1.4.
  def generate_session_id
    SecureRandom.hex(32)
  end
  # Use callbacks to share common setup or constraints between actions.
  # Loads @user from params[:id]; raises 404 when there is no such record. Internal:
  # runs as a before_action for show/edit/update/destroy.
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  # Attribute whitelist for account writes. The password is permitted as plaintext
  # here and hashed afterwards by #create / #update.
  def user_params
    params.require(:user).permit(:username, :password, :first, :last, :lastlogon)
  end
end
