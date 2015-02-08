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

  def self.iterativeSQLBuilder(sortedWordIDs, depth)
    # this is massively bad in so many ways.
    sql = ""
    sql = "select distinct e.event_id from (" if depth == 0
    word_id = sortedWordIDs.pop
    # Should I just revert to the positions table?  For some reason events_words has grown to over 43 gigs while positions is only 24.
    # Only do the generated test on the innermost subselect.  Not needed on outer selects since they are selecting from the set returned from this query.
    sql = sql + "select distinct a#{depth}.event_id from events_words as a#{depth} where a#{depth}.word_id=#{word_id}"+(sortedWordIDs.count > 0 ? " and a#{depth}.event_id in (#{iterativeSQLBuilder(sortedWordIDs, depth+1)})" : " and a#{depth}.generated>NOW()-'1 day'::interval")
    sql = sql + ") as e" if depth == 0
    return sql
  end

  def self.search(search_string)
    @events = Array.new
    event_ids = Array.new
    connection = ActiveRecord::Base.connection
    ordered_words = Hash.new

    search_string.downcase!
    terms = search_string.split(/\s+/)
    words = Word.where("text in (?)", terms).order("words.id DESC").pluck(:id)
    return [] if words.empty?

#    words.each do |word_id|
#      sql = "select count(*) from events_words where word_id=#{word_id} and generated>NOW()-'1 day'::interval"
#      results = connection.execute(sql)
#      count = results[0]["count"]
#      puts "#{word_id} was found #{count} times"
#      ordered_words[word_id] = count
#      return [] if(count == 0)
#    end

# Let's try assuming that words added later likely appear less often.
#    sql = iterativeSQLBuilder(ordered_words.sort_by{|k,v| v}, 0)
    sql = iterativeSQLBuilder(words,0)
    #sql = "select e.event_id from (select distinct a.event_id,a.word_id from events_words as a where a.generated>NOW()-'1 day'::interval and a.word_id in (#{word}) #{event_ids.empty? ? "" : "and a.event_id in (#{event_ids.join(',')})"} group by event_id,word_id) as e"
    puts sql


    #sql = "select e.event_id from (select distinct a.event_id,a.word_id from events_words as a where a.word_id in (#{words.join(",")}) group by event_id,word_id having count(distinct(a.event_id,a.word_id))=#{words.count}) as e"

    # Removed time contraint: a.generated>NOW()-'1 day'::interval and
    # Still can't get the count to work properly even with distinct in the count.  Absolutely crazy.
    # Will add back in word stat logic and rebuild the massive sub selects even though it feels really wrong.
    #  select distinct e.event_id from (select distinct a.event_id from events_words as a where a.event_id in (select distinct b.event_id from events_words as b where b.word_id=8352832 and b.generated>NOW()-'1 day'::interval) and a.word_id=8338947) as e;
    events_that_match = connection.execute(sql)
    events_that_match.map { |e| event_ids << e["event_id"]}
    @events = Event.order(generated: :asc).includes(:positions, :words).where("id in (?)", event_ids).limit(100)
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
    word_ids = Array.new()
    words.each do |word|
      dbWord = Word.find_or_add(word)

      @@pendingPositionValues.push "(#{@@nextPositionID}, #{dbWord}, #{current_position}, #{@@nextEventID})"
      # Only add a mapping for this event/word if there isn't already one - deduplicate events_words.
      @@events_words.push "(#{@@nextEventID}, #{dbWord}, '#{timestamp}')" unless word_ids.include?(dbWord)
      word_ids.push(dbWord)
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

    events_words_sql = "INSERT INTO events_words (event_id, word_id, generated) VALUES #{@@events_words.join(", ")}"
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
