# Management screens for Role records; requires the Admin right.
#
# A Role bundles Rights, and Users gain rights only through roles. Rights are
# granted to a role through #right_add / #right_remove rather than the update
# form.
class RolesController < ApplicationController
  before_action :set_role, only: [:show, :edit, :update, :destroy, :right_add, :rights]
  before_filter :authorized?

  # Replaces the inherited ApplicationController#authorized? for every
  # action in this controller. Requires the Admin right; otherwise flashes a
  # notice and redirects to the logon page. Returning false stops the action.
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
  
  # GET /roles/:id/rights -- the grant/revoke screen: shows the rights this
  # role holds plus #ungranted_rights as the candidates to add.
  def rights
    @role = Role.find(params[:id])
    @rights = @role.rights
  end
  
  # Add a right to a role
  # Grants a right to the role (params[:role]) unless it already holds it,
  # then redirects back to #rights.
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
  # Revokes a right from the role (params[:role]) if it holds it, then
  # redirects back to #rights.
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

  # Lists all roles records. No pagination or filtering.
  def index
    @roles = Role.all
  end

  # One role, addressed by id. @role is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a role.
  def new
    @role = Role.new
  end

  # Form for changing an existing role.
  def edit
  end

  # Inserts a role built from the whitelist in #role_params.
  # Re-renders the form with validation errors when the save fails.
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

  # Applies the whitelisted attributes to the @role loaded by the
  # before_action; re-renders the form on failure.
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

  # Deletes the @role.
  def destroy
    @role.destroy
    respond_to do |format|
      format.html { redirect_to roles_url, notice: 'Role was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Loads @role from params[:id]; raises 404 when no such record exists.
    # Internal: runs as a before_action.
    def set_role
      @role = Role.find(params[:id])
    end

    # Attribute whitelist for role writes; only the name is writable, since
    # membership is managed through #right_add / #right_remove.
    def role_params
      params.require(:role).permit(:name, :description, :right_id)
    end
end
