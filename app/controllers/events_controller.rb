# The search and live-dashboard screens: the primary read path into events.
#
# Events are never created or edited here -- ingestion writes them (see
# EventIngestor.storeEvent). This controller only queries and renders.
class EventsController < ApplicationController
  DEFAULT_TIMEFRAME = 3600
  DEFAULT_NUM_RESULTS = 100


  before_action :set_event, only: [:show]

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
  # :timesearch_enabled  when *ticked*, use an absolute range instead, reading the
  # :lefttime(1i..6i) / :righttime(1i..6i) datetime_select fields
  # Sets @events (a relation), @previous_search, @search_time and @search_note.
  def search
    @remote = true
    start_time = Time.now
    @num_results = requested_num_results
    @timeframe = params[:timeframe]
    @search_note = nil

    if timesearch_enabled?
      starttime = parse_datetime_params params[:lefttime], :start
      endtime = parse_datetime_params params[:righttime], :end
      if starttime.nil? || endtime.nil?
        # The box was ticked but the date fields were missing or unparseable.
        # Answering with a different window than the operator asked for would be
        # a silent lie, so report the problem and return nothing.
        @search_note = 'The date range could not be read from the form; ' \
                       'untick Timeframe Search to search a relative window.'
        @events = Event.none
      else
        @search_note = 'The search window is empty: its end precedes its start.' if endtime < starttime
        @events = Event.search(params[:search_terms], starttime..endtime, 0, @num_results)
      end
    else
      @events = Event.search(params[:search_terms], relative_window, 0, @num_results)
    end
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

  # True only when the "Timeframe Search" box is actually ticked.
  #
  # The view uses check_box, which always emits a paired hidden field, so an
  # *unticked* box still submits timesearch_enabled as {"enabled"=>"0"}. Testing
  # the presence of the key -- as this action used to -- took the absolute-date
  # branch on every form submission, using datetime_select's now->now defaults
  # and reporting 0 matches for any search.
  def timesearch_enabled?
    value = params.dig(:timesearch_enabled, :enabled)
    %w[1 true on yes].include?(value.to_s.downcase)
  end

  # The relative window, in seconds, from +timeframe+. The select always sends a
  # known value; a hand-edited or missing one must not collapse to a zero-length
  # range, which would report "0 events match" for data that is there.
  def relative_window
    seconds = params[:timeframe].to_i
    seconds = DEFAULT_TIMEFRAME if seconds <= 0
    (Time.now - seconds)..Time.now
  end

  # The select offers 50..50000; anything else (0, negative, garbage) would make
  # Event.search return nothing or an unbounded page.
  def requested_num_results
    n = params[:numresults].to_i
    n <= 0 ? DEFAULT_NUM_RESULTS : n
  end

  # Extracts a DateTime from the six Rails datetime_select fields named
  # "<label>(1i)" .. "<label>(6i)" (year, month, day, hour, minute, second).
  #
  # +utc_or_local+ selects the interpretation (:utc or :local). Returns nil when
  # the fields are missing or nonsensical; #search reports that to the operator
  # rather than passing a nil bound into searchSQL.
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
