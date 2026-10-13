# Management screens for Service records; requires the Admin right.
#
# Services are normally created implicitly during ingestion (Service.find_or_add);
# these screens exist to inspect or rename them. There is no destroy action,
# because deleting a Service would orphan the Events that reference it.
class ServicesController < ApplicationController
  before_action :set_service, only: [:show, :edit, :update]

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

  # Lists all services records. No pagination or filtering.
  def index
    @services = Service.order(name: :asc).all
  end

  # One service, addressed by id. @service is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a service.
  def new
    @service = Service.new
  end

  # Form for changing an existing service.
  def edit
  end

  # Inserts a service built from the whitelist in #service_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @service = Service.new(service_params)

    respond_to do |format|
      if @service.save
        format.html { redirect_to @service, notice: 'Service was successfully created.' }
        format.json { render action: 'show', status: :created, location: @service }
      else
        format.html { render action: 'new' }
        format.json { render json: @service.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @service loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @service.update(service_params)
        format.html { redirect_to @service, notice: 'Service was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @service.errors, status: :unprocessable_entity }
      end
    end
  end


  private
    # Loads @service from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_service
      @service = Service.find(params[:id])
    end

    # Attribute whitelist for service writes; any param not
    # listed here is dropped before it reaches the model.
    def service_params
      params.require(:service).permit(:description)
    end
end
