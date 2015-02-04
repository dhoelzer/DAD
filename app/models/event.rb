class Event < ActiveRecord::Base
  has_many :positions
  has_many :words, :through => :positions
  belongs_to :system
  belongs_to :service

  BULK_INSERT_SIZE=(Rails.env.development? ? 1 : 2000)
  @@nextEventID = -1
  @@nextPositionID = -1
  @@pendingEventValues = Array.new
  @@pendingPositionValues = Array.new
  @@events_words = Array.new
  @@start_time = Time.now


  def self.search(search_string)
    @events = Array.new
    event_ids = Array.new
    connection = ActiveRecord::Base.connection
    ordered_words = Hash.new

    search_string.downcase!
    terms = search_string.split(/\s+/)
    words = Word.where("text in (?)", terms).pluck(:id)
    return [] if words.empty?
    sql = "select e.event_id from (select distinct a.event_id,a.word_id from events_words as a where a.generated>NOW()-'1 day'::interval and a.word_id in (#{words.join(",")}) group by event_id,word_id having count(*)=#{words.count}) as e"
    puts sql
    events_that_match = connection.execute(sql)
    events_that_match.map { |e| event_ids << e["event_id"]}
    event_ids = event_ids[-100,100]
    @events = Event.order(generated: :asc).includes(:positions, :words).where("id in (?)", event_ids)
    return (@events.nil? ? [] : @events)
  end    

  def self.storeEvent(eventString)
    split_text = eventString.split(/\s+/)
    txtsystem = split_text[0]
    return unless split_text.size > 1 # If there's no date and only an IP then it's not a valid message.
    system = System.find_or_add(txtsystem)
    txttimestamp = split_text[1..3].join(' ')
    timestamp = (split_text[1] == "Dec" ? DateTime.parse("#{txttimestamp} 2014 GMT") : DateTime.parse("#{txttimestamp} 2015 GMT"))
    txtservice = split_text[5]
    txtservice.tr!("^a-zA-Z/\-", "")
    service = Service.find_or_add(txtservice)

    if @@nextEventID == -1 then
      if Event.all.count == 0 then
        @@nextEventID = 1
        @@nextPositionID = 1
      else
        @@nextEventID = Event.last.id + 1 if @@nextEventID == -1
        @@nextPositionID = Position.last.id + 1 if @@nextPositionID == -1
      end
    end
    @@pendingEventValues.push "(#{@@nextEventID}, #{system.id}, #{service.id}, '#{timestamp}', '#{Time.now}')"
    #    event = Event.create(:system_id => system.id, :service_id => service.id, :generated => timestamp, :stored => Time.now)
    #    return nil if event.nil?

    eventString.downcase!
    eventString.tr!("\r\n", "")
    eventString.gsub!(/([^a-zA-Z0-9\-.:])/," \\1 " )
    words = eventString.split(/\s+/)
    current_position = 0                  # Track which position we are at within the event
    words.each do |word|
      dbWord = Word.find_or_add(word)

      @@pendingPositionValues.push "(#{@@nextPositionID}, #{dbWord}, #{current_position}, #{@@nextEventID})"
      @@events_words.push "(#{@@nextEventID}, #{dbWord}, '#{timestamp}')"
      #      position = Position.create(:word_id => dbWord.id, :position => current_position, :event_id => event.id)
      @@nextPositionID += 1
      current_position += 1
    end
    @@nextEventID += 1
    self.performPendingInserts if @@pendingEventValues.count >= BULK_INSERT_SIZE
  end

  def self.performPendingInserts
    return if @@pendingEventValues.count < 1
    connection = ActiveRecord::Base.connection

    event_sql = "INSERT INTO events (id, system_id, service_id, generated, stored) VALUES #{@@pendingEventValues.join(", ")}"
    connection.execute event_sql

    positions_sql = "INSERT INTO positions (id, word_id, position, event_id) VALUES #{@@pendingPositionValues.join(", ")}"
    connection.execute positions_sql

    events_words_sql = "INSERT INTO events_words (event_id, word_id) VALUES #{@@events_words.join(", ")}"
    connection.execute events_words_sql

    puts "\t\t-->> Flushed #{@@pendingEventValues.count} events with #{@@pendingPositionValues.count} positions. <<--"
    elapsed_time = (Time.now - @@start_time)
    puts "\t\t-->> Started run: #{@@start_time}\t#{elapsed_time} seconds elapsed\t#{@@pendingEventValues.count/elapsed_time} events processed per second."
    @@start_time = Time.now
    @@pendingEventValues = []
    @@pendingPositionValues = []
    @@events_words = []
  end
end
