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
    @term_strings = params[:search_terms].downcase
    @terms = @term_strings.split(/\s+/)
    events = Array.new
    words = Word.where("text in (?)", @terms).pluck(:id)
    connection = ActiveRecord::Base.connection
    joins = "select distinct a.event_id from events_words as a"
    ref="b"
    words.each do |word|
      joins << " inner join events_words as #{ref} on a.event_id=#{ref}.event_id and #{ref}.word_id=#{word}"
      ref = (ref.ord+1).chr
    end
    event_sql = joins
    events_that_match = connection.execute event_sql
    event_ids = Array.new
    events_that_match.map { |e| event_ids << e["event_id"] }
    @events = Event.order(generated: :asc).includes(:positions, :words).where("id in (?)", event_ids).offset(0).limit(40)
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
