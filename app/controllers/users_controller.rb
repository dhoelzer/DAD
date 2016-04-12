class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_filter :authorized?, except: [:logon, :do_logon, :logoff]

  # Override default authorized? from app controller
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

  # GET /users
  # GET /users.json
  def index
    @users = User.all
  end

  # GET /users/1
  # GET /users/1.json
  def show
  end

  def roles
    @user = User.find(params[:id])
    @roles = @user.roles
  end

  # Add a role to a user
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


  # POST /users/do_logon
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
      if Rails.env == "development" then
        cookies[:sessionID] = { value: @session.session_hash, httponly: true, secure: false, expires: Time.now+3600 }
      else
        cookies[:sessionID] = { value: @session.session_hash, httponly: true, secure: true, expires: Time.now+3600 }
      end
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

  def logoff
    if !@current_user.nil? && !@current_user.session.nil?
      session = @current_user.session
      session.destroy!
    end
    cookies[:sessionID] = nil
    @current_user = nil
    redirect_to "/"
  end

  # GET /users/logon
  def logon
    @logon = User.new
  end

  # GET /users/new
  def new
    @user = User.new
  end

  # GET /users/1/edit
  def edit
  end

  # POST /users
  # POST /users.json
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

  # PATCH/PUT /users/1
  # PATCH/PUT /users/1.json
  def update
    respond_to do |format|
      if @user.update(user_params)
        @user.attempts = 0
        puts(params)
        puts "storing password -#{params[:password]}-"
        @user.store_password(params[:password])
        @user.save
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1
  # DELETE /users/1.json
  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_to users_url, notice: 'User was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  def generate_session_id
    length = 64
    field = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    field = field + field.downcase
    field = field + "0123456789"
    field = field.split(//)
    i=length
    random_id = ""
    i.downto(1) { random_id = random_id + field[rand(10000)%field.count] }
    return random_id
  end
  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def user_params
    params.require(:user).permit(:username, :password, :first, :last, :lastlogon)
  end
end
