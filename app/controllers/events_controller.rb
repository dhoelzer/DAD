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
    @terms.each do |term|
      word = Word.find_by_text(term)
      events_that_match = (word.nil? ? [] : word.events.pluck(:id))
      events << events_that_match
    end
    @events = events[0] unless events.empty?
    events.each { |e| @events = @events & e }
    @events = Event.includes(:positions, :words).order(generated: :asc).where("id in (?)", @events).offset(0).limit(40)
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
