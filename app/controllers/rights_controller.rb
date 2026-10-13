# Management screens for Right records; requires the Admin right.
#
# Rights are the permission atoms ("Viewer", "Commentator", "Detective",
# "Taskmaster", "Admin") that User#has_right? and every controller's authorized?
# check. Renaming or deleting one silently changes what those checks mean.
class RightsController < ApplicationController
  before_action :set_right, only: [:show, :edit, :update, :destroy]
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
  

  # Lists all rights records. No pagination or filtering.
  def index
    @rights = Right.all
  end

  # One right, addressed by id. @right is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a right.
  def new
    @right = Right.new
  end

  # Form for changing an existing right.
  def edit
  end

  # Inserts a right built from the whitelist in #right_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @right = Right.new(right_params)

    respond_to do |format|
      if @right.save
        format.html { redirect_to @right, notice: 'Right was successfully created.' }
        format.json { render :show, status: :created, location: @right }
      else
        format.html { render :new }
        format.json { render json: @right.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @right loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @right.update(right_params)
        format.html { redirect_to @right, notice: 'Right was successfully updated.' }
        format.json { render :show, status: :ok, location: @right }
      else
        format.html { render :edit }
        format.json { render json: @right.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @right.
  def destroy
    @right.destroy
    respond_to do |format|
      format.html { redirect_to rights_url, notice: 'Right was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Loads @right from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_right
      @right = Right.find(params[:id])
    end

    # Attribute whitelist for right writes; any param not
    # listed here is dropped before it reaches the model.
    def right_params
      params.require(:right).permit(:name, :description)
    end
end
