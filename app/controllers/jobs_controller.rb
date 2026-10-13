# Management screens for Job records; requires the Taskmaster right.
#
# Job#script names an entry in the JobHandler::HANDLERS registry, which the
# scheduler looks up by name; no user-authored code is executed, so creating a
# Job can no longer run arbitrary Ruby on the host.
class JobsController < ApplicationController
  before_action :set_job, only: [:show, :edit, :update, :destroy]

  # Debug aid: renders @job.script back to the view without evaluating it, so an
  # operator can confirm what a Job would run. Note @job is only loaded by the
  # before_action for show/edit/update/destroy, so this action 500s as routed.
  def test
    @output = @job.script
  end
  # Replaces the inherited ApplicationController#authorized? for every
  # action in this controller. Requires the Taskmaster right; otherwise flashes a
  # notice and redirects to the logon page. Returning false stops the action.
  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Taskmaster"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # Lists all jobs records. No pagination or filtering.
  def index
    @jobs = Job.all
  end

  # One job, addressed by id. @job is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a job.
  def new
    @job = Job.new
  end

  # Form for changing an existing job.
  def edit
  end

  # Inserts a job built from the whitelist in #job_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @job = Job.new(job_params)
    @job.user_id = @current_user.id
    respond_to do |format|
      if @job.save
        format.html { redirect_to @job, notice: 'Job was successfully created.' }
        format.json { render action: 'show', status: :created, location: @job }
      else
        format.html { render action: 'new' }
        format.json { render json: @job.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @job loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @job.update(job_params)
        @job.user_id = @current_user.id
        @job.save
        format.html { redirect_to @job, notice: 'Job was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @job.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @job.
  def destroy
    @job.destroy
    respond_to do |format|
      format.html { redirect_to jobs_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @job from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_job
      @job = Job.find(params[:id])
    end

    # Attribute whitelist for job writes; any param not
    # listed here is dropped before it reaches the model.
    def job_params
      params.require(:job).permit(:name, :description, :user_id, :script, :last_event_id, :last_run, :next_run, :frequency)
    end
end
