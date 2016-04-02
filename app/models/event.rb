class Event < ActiveRecord::Base
  has_many :positions
  has_many :words, :through => :positions
  has_and_belongs_to_many :alerts
  belongs_to :system
  belongs_to :service

  BULK_INSERT_SIZE=((Rails.env.development? || Rails.env.test?) ? 1 : 4000)
  @@nextEventID = -1
  @@nextPositionID = -1
  @@pendingEventValues = Set.new
  @@pendingPositionValues = Set.new
  @@events_words = Set.new
  @@start_time = Time.now
  @display_helper = nil       # Using lazy initialization but still using instance vars so that we
  @event_fields = nil         # instantiate lazily but still only do one SQL query per event
  @@current_year = Time.new.year
  
  def self.hidden?(current_user = nil)
    return true if current_user.nil?
    return true unless current_user.has_right?("Viewer")
    return false
  end
  
  def display_helper
    @display_helper = @display_helper.nil? ? Display.helper_for_event(self.inspect) : @display_helper
    @display_helper
  end
  
  def use_display_helper?
    return (self.display_helper.nil? ? false : true)
  end
  
  def parsed
    @display_helper = self.display_helper
    return "BAD DISPLAY FILTER" if @display_helper.nil?
    eval @display_helper.display_script
    parse_event(self.inspect)
  end
  
  def event_fields
    return @event_fields unless @event_fields.nil?
    @event_fields = Array.new
    self.positions.order(:position).each do |position|
      @event_fields << position.word.text
    end
    @event_fields
  end
  
  def reconstitute
    string = ""
		self.positions.order(:position).each do |position|
      string = string + "#{position.word.text} "
    end
    return string
  end
  
  def inspect
    string = "#{self.system.display_name}|#{self.generated}|"
		self.positions.order(:position).each do |position|
      string = "#{string} #{position.word.text}"
    end
    return string
  end

  def self.diskUtilization
    `df -m | egrep "\s+/$"`.split(/\s+/)[4].to_i
  end
  
  def self.resetStats
    @@start_time = Time.now
  end
  
  def self.search(search_string, starting_time=(Time.now - 1.hour), offset=0, limit=100)
    @events = Array.new
    event_ids = Array.new
    connection = ActiveRecord::Base.connection
    
    terms = search_string.downcase.split(/\s+/)
    return [] if terms.empty?
    sql = "select event_id from events_words where generated>'#{starting_time.to_s(:db)}' and word_id in (select id from words where words.text in ('#{terms.join("', '")}')) group by event_id having count(distinct(word_id))=#{terms.count}"
    events_that_match = connection.execute(sql)
    events_that_match.map { |e| event_ids << e[0]}
    @events = Event.order(generated: :asc).includes(:positions, :words).where("id in (?)", event_ids).limit(limit).offset(offset)
    return (@events.nil? ? [] : @events)    
  end 
  
  def self.iterativeSQLBuilder(sortedWordIDs, depth, starting_time)
    # this is massively bad in so many ways.
    sql = ""
    sql = "select distinct e.event_id from (" if depth == 0
    word_id = sortedWordIDs.pop
    # Should I just revert to the positions table?  For some reason events_words has grown to over 43 gigs while positions is only 24.
    # Only do the generated test on the innermost subselect.  Not needed on outer selects since they are selecting from the set returned from this query.
    sql = sql + "select distinct a#{depth}.event_id from events_words as a#{depth} where a#{depth}.word_id=#{word_id}"+(sortedWordIDs.count > 0 ? " and a#{depth}.event_id in (#{iterativeSQLBuilder(sortedWordIDs, depth+1, starting_time)})" : " and a#{depth}.generated>'#{starting_time.to_s(:db)}'")
    sql = sql + ") as e" if depth == 0
    return sql
  end


  
  def self.search2(search_string, starting_time=(Time.now - 1.hour), offset=0, limit=100)
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
    sql = iterativeSQLBuilder(words,0, starting_time)
    #sql = "select e.event_id from (select distinct a.event_id,a.word_id from events_words as a where a.generated>NOW()-'1 day'::interval and a.word_id in (#{word}) #{event_ids.empty? ? "" : "and a.event_id in (#{event_ids.join(',')})"} group by event_id,word_id) as e"
    puts sql


    #sql = "select e.event_id from (select distinct a.event_id,a.word_id from events_words as a where a.word_id in (#{words.join(",")}) group by event_id,word_id having count(distinct(a.event_id,a.word_id))=#{words.count}) as e"

    # Removed time contraint: a.generated>NOW()-'1 day'::interval and
    # Still can't get the count to work properly even with distinct in the count.  Absolutely crazy.
    # Will add back in word stat logic and rebuild the massive sub selects even though it feels really wrong.
    #  select distinct e.event_id from (select distinct a.event_id from events_words as a where a.event_id in (select distinct b.event_id from events_words as b where b.word_id=8352832 and b.generated>NOW()-'1 day'::interval) and a.word_id=8338947) as e;
    events_that_match = connection.execute(sql)
    events_that_match.map { |e| event_ids << e[0]}
    @events = Event.order(generated: :asc).includes(:positions, :words).where("id in (?)", event_ids).limit(limit).offset(offset)
    return (@events.nil? ? [] : @events)
  end    

  def self.storeEvent(eventString)
    # This next line is to seek and destroy invalid UTF-8 byte sequences.  They seem to show up in some
    # logs sometimes in URLs.
    eventString = eventString.encode('UTF-8', :invalid => :replace)
    split_text = eventString.split(/\s+/)
    if split_text.count < 6 then
      puts "Invalid for syslog format: Too few fields -> #{eventString}"
      return
    end
    txtsystem = split_text[0]
    return unless split_text.size > 1 # If there's no date and only an IP then it's not a valid message.
    system = System.find_or_add(txtsystem)
    if split_text[3].to_i > 2014 && split_text[3].to_i < 2020 then
      txttimestamp = split_text[1..4].join(' ')
      begin
        timestamp = DateTime.parse("#{txttimestamp} GMT")
      rescue Exception => e
        puts "#{e}: #{eventString}"
        return
      end
    else
      txttimestamp = split_text[1..3].join(' ')
      begin
        timestamp = DateTime.parse("#{txttimestamp} #{@@current_year} GMT")
      rescue Exception => e
        puts "#{e}: #{eventString}"
        return
      end
    end
    txtservice = split_text[5]
    txtservice = txtservice.tr("^a-zA-Z\-_/","")
    service = Service.find_or_add(txtservice)
    #puts("#{@@nextEventID}: #{txttimestamp} #{txtsystem}(#{system.id}) #{txtservice}(#{service.id})")
    if @@nextEventID == -1 then
      if Event.all.count == 0 then
        @@nextEventID = 1
        @@nextPositionID = 1
      else
        @@nextEventID = Event.order(id: :desc).limit(1)[0].id + 1 if @@nextEventID == -1
        @@nextPositionID = Position.order(id: :desc).limit(1)[0].id + 1 if @@nextPositionID == -1
      end
    end
    @@pendingEventValues.add "(#{@@nextEventID}, #{system.id}, #{service.id}, '#{timestamp.to_s(:db)}', '#{Time.now.to_s(:db)}')"
    #    event = Event.create(:system_id => system.id, :service_id => service.id, :generated => timestamp, :stored => Time.now)
    #    return nil if event.nil?

    eventString.downcase!
    eventString.tr!("\r\n", "")
    eventString.gsub!(/([^a-zA-Z0-9 \-:_@\*\/.])/," \\1 " )
#    words = eventString.split(/\s+/) # This seems like a redundant split..
    current_position = 0                  # Track which position we are at within the event
    word_ids = Set.new()
    split_text.each do |word| # changed from words.. I think we already have this.
      dbWord = Word.find_or_add(word)
      @@pendingPositionValues.add "(#{@@nextPositionID}, #{dbWord}, #{current_position}, #{@@nextEventID})"
      # Only add a mapping for this event/word if there isn't already one - deduplicate events_words.
      @@events_words.add "(#{@@nextEventID}, #{dbWord}, '#{timestamp.to_s(:db)}')" unless word_ids.include?(dbWord)
      word_ids.add(dbWord)
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

    #puts "Current event_id: #{@@nextEventID} - last: #{@@pendingEventValues[0]}" # Can't do this with a set
    events_words_sql = "INSERT INTO events_words (event_id, word_id, generated) VALUES #{@@events_words.to_a.join(", ")}"
    connection.execute events_words_sql
    # Let's insert the words first so that we don't have to do it again.
    
    event_sql = "INSERT INTO events (id, system_id, service_id, generated, stored) VALUES #{@@pendingEventValues.to_a.join(", ")}"
    connection.execute event_sql

    positions_sql = "INSERT INTO positions (id, word_id, position, event_id) VALUES #{@@pendingPositionValues.to_a.join(", ")}"
    connection.execute positions_sql


    puts "\t\t-->> Flushed #{@@pendingEventValues.count} events with #{@@pendingPositionValues.count} positions. <<--"
    elapsed_time = (Time.now - @@start_time)
    eventsPerSecond = @@pendingEventValues.count/elapsed_time
    puts "\t\t-->> Started run: #{@@start_time}\t#{elapsed_time} seconds elapsed\t#{eventsPerSecond} events processed per second."
    Statistic.logEventsPerSecond(eventsPerSecond)
    @@start_time = Time.now
    @@pendingEventValues = []
    @@pendingPositionValues = []
    @@events_words = []
    @@current_year = Time.new.year
  end
end
