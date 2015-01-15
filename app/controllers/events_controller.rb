class EventsController < ApplicationController
  before_action :set_event, only: [:show]

  # GET /events
  # GET /events.json
  def index
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end



  def search
    @events = Event.search(params[:search_terms])
  end
  
  # GET /events/1
  # GET /events/1.json
  def show
  end
  
  private
    # Use callbacks to share common setup or constraints between actions.
    def set_event
      @event = Event.find(params[:id])
    end
end
