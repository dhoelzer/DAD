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
    @remote = true
    start_time = Time.now
    @num_results = params[:numresults].to_i
    @timeframe = params[:timeframe]
    if (params[:timesearch_enabled]) then
      lefttime = params[:lefttime]
      righttime = params[:righttime]
      starttime = parse_datetime_params lefttime, :start
      endtime = parse_datetime_params righttime, :end

    end
    @events = Event.search(params[:search_terms], Time.now - @timeframe.to_i, 0, @num_results) unless params[:timesearch_enabled]
    @events = Event.search_period(params[:search_terms, starttime, endtime, 0, @num_results]) if params[:timesearch_enabled]
    @previous_search = params[:search_terms]
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

  #extract a datetime object from params, useful for receiving datetime_select attributes
  #out of any activemodel
  def parse_datetime_params params, label, utc_or_local = :utc
    begin
      year   = params[(label.to_s + '(1i)')].to_i
      month  = params[(label.to_s + '(2i)')].to_i
      mday   = params[(label.to_s + '(3i)')].to_i
      hour   = (params[(label.to_s + '(4i)')] || 0).to_i
      minute = (params[(label.to_s + '(5i)')] || 0).to_i
      second = (params[(label.to_s + '(6i)')] || 0).to_i

      return DateTime.civil_from_format(utc_or_local,year,month,mday,hour,minute,second)
    rescue => e
      return nil
    end
  end

end
