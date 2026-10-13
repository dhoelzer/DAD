# Management screens for Statistic records; requires the Admin right.
#
# Statistics are append-only samples written by the ingestion pipeline and charted
# on the dashboard. The CRUD actions exist for correcting or backfilling series.
class StatisticsController < ApplicationController
  before_action :set_statistic, only: [:show, :edit, :update, :destroy]

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

  # Lists all statistics records. No pagination or filtering.
  def index
    @statistics = Statistic.all
  end

  # One statistic, addressed by id. @statistic is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a statistic.
  def new
    @statistic = Statistic.new
  end

  # Form for changing an existing statistic.
  def edit
  end

  # Inserts a statistic built from the whitelist in #statistic_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @statistic = Statistic.new(statistic_params)

    respond_to do |format|
      if @statistic.save
        format.html { redirect_to @statistic, notice: 'Statistic was successfully created.' }
        format.json { render action: 'show', status: :created, location: @statistic }
      else
        format.html { render action: 'new' }
        format.json { render json: @statistic.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @statistic loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @statistic.update(statistic_params)
        format.html { redirect_to @statistic, notice: 'Statistic was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @statistic.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @statistic.
  def destroy
    @statistic.destroy
    respond_to do |format|
      format.html { redirect_to statistics_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @statistic from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_statistic
      @statistic = Statistic.find(params[:id])
    end

    # Attribute whitelist for statistic writes; any param not
    # listed here is dropped before it reaches the model.
    def statistic_params
      params.require(:statistic).permit(:type_id, :timestamp, :system_id, :service_id, :stat)
    end
end
