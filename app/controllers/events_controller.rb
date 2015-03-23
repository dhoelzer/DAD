class EventsController < ApplicationController
  before_action :set_event, only: [:show]

  def authorized?  
    if @current_user.nil? then
      flash[:notice] = "Not authorized"
      redirect_to logon_users_path
      return false
    end
    return true if(@current_user.has_right?("Viewer"))
    flash[:notice] = "You lack the appropriate rights"
    redirect_to logon_users_path
    return false
  end

  # GET /events
  # GET /events.json
  def index
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end

  def recent
    respond_to do |format|
      format.js { render layout: false }
    end
  end

  def search
    start_time = Time.now
    @events = Event.search(params[:search_terms], Time.now - params[:timeframe].to_i)
    @previous_search = params[:search_terms]
    @timeframe = params[:timeframe]
    @search_time = Time.now - start_time
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
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
