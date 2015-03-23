class RolesController < ApplicationController
  before_action :set_role, only: [:show, :edit, :update, :destroy, :right_add, :rights]
  before_filter :authorized?

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
  
  def rights
    @role = Role.find(params[:id])
    @rights = @role.rights
  end
  
  # Add a right to a role
  def right_add
    @role = Role.find(params[:id])
    @right = Right.find(params[:right])
    
    if not @role.has_right?(@right)
      @role.rights << @right
      flash[:notice] = "Right successfully added to role."
    else
      flash[:notice] = "That role already has that right!"
    end
    redirect_to :action => :rights, :id => @role
  end

  # Remove a right to a role
  def right_remove
    @role = Role.find(params[:id])
    @right = Right.find(params[:right])
    
    if @role.has_right?(@right)
      @role.rights = @role.rights - [@right]
      flash[:notice] = "Right successfully removed to role."
    else
      flash[:notice] = "That role doesn't have that right!"
    end
    redirect_to :action => :rights, :id => @role
  end

  # GET /roles
  # GET /roles.json
  def index
    @roles = Role.all
  end

  # GET /roles/1
  # GET /roles/1.json
  def show
  end

  # GET /roles/new
  def new
    @role = Role.new
  end

  # GET /roles/1/edit
  def edit
  end

  # POST /roles
  # POST /roles.json
  def create
    @role = Role.new(role_params)

    respond_to do |format|
      if @role.save
        format.html { redirect_to @role, notice: 'Role was successfully created.' }
        format.json { render :show, status: :created, location: @role }
      else
        format.html { render :new }
        format.json { render json: @role.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /roles/1
  # PATCH/PUT /roles/1.json
  def update
    respond_to do |format|
      if @role.update(role_params)
        format.html { redirect_to @role, notice: 'Role was successfully updated.' }
        format.json { render :show, status: :ok, location: @role }
      else
        format.html { render :edit }
        format.json { render json: @role.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /roles/1
  # DELETE /roles/1.json
  def destroy
    @role.destroy
    respond_to do |format|
      format.html { redirect_to roles_url, notice: 'Role was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_role
      @role = Role.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def role_params
      params.require(:role).permit(:name, :description, :right_id)
    end
end
