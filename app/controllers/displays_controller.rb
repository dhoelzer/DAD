# Management screens for Display records; requires the Detective right.
#
# A Display pairs a regex that recognises a log format with Ruby that renders it.
# WARNING: Display#display_script is eval'd by Event#parsed, so create/edit here
# is arbitrary code execution as the web process user.
class DisplaysController < ApplicationController
  before_action :set_display, only: [:show, :edit, :update, :destroy]

  # Replaces the inherited ApplicationController#authorized? for every
  # action in this controller. Requires the Detective right; otherwise flashes a
  # notice and redirects to the logon page. Returning false stops the action.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Detective"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # Lists all displays records. No pagination or filtering.
  def index
    @displays = Display.all
  end

  # One display, addressed by id. @display is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a display.
  def new
    @display = Display.new
  end

  # Form for changing an existing display.
  def edit
  end

  # Inserts a display built from the whitelist in #display_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @display = Display.new(display_params)

    respond_to do |format|
      if @display.save
        format.html { redirect_to @display, notice: 'Display was successfully created.' }
        format.json { render action: 'show', status: :created, location: @display }
      else
        format.html { render action: 'new' }
        format.json { render json: @display.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @display loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @display.update(display_params)
        format.html { redirect_to @display, notice: 'Display was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @display.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @display.
  def destroy
    @display.destroy
    respond_to do |format|
      format.html { redirect_to displays_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @display from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_display
      @display = Display.find(params[:id])
    end

    # Attribute whitelist for display writes; any param not
    # listed here is dropped before it reaches the model.
    def display_params
      params.require(:display).permit(:key, :name, :description, :display_script, :user_id)
    end
end
