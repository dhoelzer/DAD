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
    joins = "select distinct e.id from events as e where"
    join=0
    words.each do |word|
      joins << "#{ (join==0 ? ' ' : ' and ') }exists(select event_id from events_words where event_id=e.id and word_id=#{word})"
      join += 1
    end
    event_sql = "#{joins} limit 100"
    puts joins
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
