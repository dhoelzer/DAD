# Management screens for System records; requires the Viewer right.
#
# Systems are created implicitly during ingestion, keyed by address. #create and
# #update let an operator attach a friendlier display name. There is no destroy
# action, because deleting a System would orphan the Events that reference it.
class SystemsController < ApplicationController
  before_action :set_system, only: [:show, :edit, :update]

  # Lists all systems records. No pagination or filtering.
  def index
    #@systems = System.order(name: :asc).all
    @systems = System.with_events_within_hours(24)
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end

  # One system, addressed by id. @system is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
    @events = Event.where(:system => @system).limit(25).order(generated: :desc).reverse
  end

  # Blank form for creating a system.
  def new
    @system = System.new
  end

  # Form for changing an existing system.
  def edit
  end

  # Inserts a system built from the whitelist in #system_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @system = System.new(system_params)

    respond_to do |format|
      if @system.save
        format.html { redirect_to @system, notice: 'System was successfully created.' }
        format.json { render action: 'show', status: :created, location: @system }
      else
        format.html { render action: 'new' }
        format.json { render json: @system.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @system loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @system.update(system_params)
        format.html { redirect_to @system, notice: 'System was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @system.errors, status: :unprocessable_entity }
      end
    end
  end


  private
    # Loads @system from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_system
      @system = System.find(params[:id])
    end

    # Attribute whitelist for system writes; any param not
    # listed here is dropped before it reaches the model.
    def system_params
      params.require(:system).permit(:address, :description, :administrator, :contact_email, :monitor, :name)
    end
end
