# Management screens for Exclusion records; requires the Commentator right.
#
# An Exclusion#pattern is used as a regex by Event.recent_events to hide matching
# lines from the live dashboard. A malformed pattern breaks the dashboard for
# every user, not just the author's.
class ExclusionsController < ApplicationController
  before_action :set_exclusion, only: [:show, :edit, :update, :destroy]


  # Lists all exclusions records. No pagination or filtering.
  def index
    @exclusions = Exclusion.all
  end

  # One exclusion, addressed by id. @exclusion is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a exclusion.
  def new
    @exclusion = Exclusion.new
    @exclusion.user = @current_user
  end

  # Form for changing an existing exclusion.
  def edit
  end

  # Inserts a exclusion built from the whitelist in #exclusion_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @exclusion = Exclusion.new(exclusion_params)
    @exclusion.user = @current_user
    respond_to do |format|
      if @exclusion.save
        format.html { redirect_to @exclusion, notice: 'Exclusion was successfully created.' }
        format.json { render action: 'show', status: :created, location: @exclusion }
      else
        format.html { render action: 'new' }
        format.json { render json: @exclusion.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @exclusion loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @exclusion.update(exclusion_params)
        @exclusion.user = @current_user
        format.html { redirect_to @exclusion, notice: 'Exclusion was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @exclusion.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @exclusion.
  def destroy
    @exclusion.destroy
    respond_to do |format|
      format.html { redirect_to exclusions_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @exclusion from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_exclusion
      @exclusion = Exclusion.find(params[:id])
    end

    # Attribute whitelist for exclusion writes; any param not
    # listed here is dropped before it reaches the model.
    def exclusion_params
      params.require(:exclusion).permit(:pattern, :user_id)
    end
end
