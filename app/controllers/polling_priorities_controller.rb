# Editing the polling interval bands.
#
# Index is readable by a Viewer so the guarantee each priority offers is visible
# next to the hosts relying on it; editing is Admin, since widening a band
# directly loosens how often DAD checks a host for new events.
#
# No new/destroy here. Levels are added by a migration or a console for now --
# the requirement asks that more levels be *possible* later, and the schema
# already allows that without a code change.
class PollingPrioritiesController < ApplicationController
  before_action :set_polling_priority, only: [:edit, :update]

  def index
    @polling_priorities = PollingPriority.ordered
  end

  def edit
  end

  def update
    respond_to do |format|
      if @polling_priority.update(polling_priority_params)
        format.html { redirect_to polling_priorities_path, notice: 'Priority was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @polling_priority.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_polling_priority
    @polling_priority = PollingPriority.find(params[:id])
  end

  def polling_priority_params
    params.require(:polling_priority)
          .permit(:name, :rank, :min_interval_secs, :max_interval_secs, :enabled)
  end
end
