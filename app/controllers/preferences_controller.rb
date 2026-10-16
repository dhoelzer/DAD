# Management screens for Preference records.
#
# Only the user_id 0 row is meaningful: it holds the live dashboard's page size
# (see Preference.eventsDashboard). The remaining CRUD actions operate on rows
# nothing reads.
#
# This controller defines no authorized? override, so the inherited
# ApplicationController gate applies: any logged-in user may edit preferences.
class PreferencesController < ApplicationController
  before_action :set_preference, only: [:show, :edit, :update, :destroy]

  # Lists all preferences records. No pagination or filtering.
  def index
    @preferences = Preference.all
  end

  # One preference, addressed by id. @preference is loaded by the
  # before_action; the .json form returns the record as JSON.
  def show
  end

  # Blank form for creating a preference.
  def new
    @preference = Preference.new
  end

  # Form for changing an existing preference.
  def edit
  end

  # Inserts a preference built from the whitelist in #preference_params.
  # Re-renders the form with validation errors when the save fails.
  def create
    @preference = Preference.new(preference_params)

    respond_to do |format|
      if @preference.save
        format.html { redirect_to @preference, notice: 'Preference was successfully created.' }
        format.json { render action: 'show', status: :created, location: @preference }
      else
        format.html { render action: 'new' }
        format.json { render json: @preference.errors, status: :unprocessable_entity }
      end
    end
  end

  # Applies the whitelisted attributes to the @preference loaded by the
  # before_action; re-renders the form on failure.
  def update
    respond_to do |format|
      if @preference.update(preference_params)
        format.html { redirect_to @preference, notice: 'Preference was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @preference.errors, status: :unprocessable_entity }
      end
    end
  end

  # Deletes the @preference.
  def destroy
    @preference.destroy
    respond_to do |format|
      format.html { redirect_to preferences_url }
      format.json { head :no_content }
    end
  end

  private
    # Loads @preference from params[:id]; raises 404 when no such
    # record exists. Internal: runs as a before_action.
    def set_preference
      @preference = Preference.find(params[:id])
    end

    # Attribute whitelist for preference writes; any param not
    # listed here is dropped before it reaches the model.
    def preference_params
      params.require(:preference).permit(:user_id, :liveEventsDisplayed, :dashboardElements, :archiveFreeSpacePercent)
    end
end
