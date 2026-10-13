# The search and live-dashboard screens: the primary read path into events.
#
# Events are never created or edited here -- ingestion writes them (see
# Event.storeEvent). This controller only queries and renders.
class EventsController < ApplicationController
  before_action :set_event, only: [:show]

  # Requires the Viewer right; replaces the ApplicationController default.
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

  # GET /events (and .json) -- the live dashboard page. No records are loaded here;
  # the view and the polling #recent action pull them via Event.recent_events.
  def index
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end

  # GET /events/recent (JS only) -- polling endpoint backing the live dashboard.
  # Renders recent.js.erb, which replaces the event list in place. Data comes from
  # Event.recent_events, which applies the Exclusion patterns and self-tunes how many
  # rows to fetch.
  def recent
    respond_to do |format|
      format.js { render layout: false }
    end
  end

  # GET/POST /events/search (HTML and JS) -- runs a full-text search and renders the
  # result page. Expects:
  # :search_terms        whitespace-separated terms, all of which must match
  # :timeframe           seconds to look back (relative-range form)
  # :numresults          maximum events to return (also the page size)
  # :timesearch_enabled  when present, use an absolute range instead, reading the
  # :lefttime(1i..6i) / :righttime(1i..6i) datetime_select fields
  # Sets @events (a relation), @previous_search and @search_time for the view.
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
    @events = Event.search_period(params[:search_terms], starttime, endtime, 0, @num_results) if params[:timesearch_enabled]
    @previous_search = params[:search_terms]
    @search_time = Time.now - start_time
    respond_to do |format|
      format.html
      format.js {render layout: false}
    end
  end
  
  # GET /events/1 (and .json) -- single event detail page; @event is loaded by the
  # #set_event before_action.
  def show
  end
  
  private
    # Use callbacks to share common setup or constraints between actions.
    # Loads @event from params[:id]; raises 404 when there is no such record.
    # Internal: runs as a before_action for #show.
    def set_event
      @event = Event.find(params[:id])
    end

  # Extracts a DateTime from the six Rails datetime_select fields named
  # "<label>(1i)" .. "<label>(6i)" (year, month, day, hour, minute, second).
  #
  # +utc_or_local+ selects the interpretation (:utc or :local). Returns nil when the
  # fields are missing or nonsensical, so callers must handle nil -- note #search
  # currently passes the result to Event.search_period unchecked.
  #
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
