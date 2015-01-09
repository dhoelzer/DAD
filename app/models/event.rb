class Event < ActiveRecord::Base
  has_many :positions
  has_many :words, :through => :positions
  belongs_to :system
  belongs_to :service
  
  @@nextEventID = -1
  @@nextPositionID = -1
  @@pendingEventValues = Array.new
  @@pendingPositionValues = Array.new
  
  def self.storeEvent(eventString)
    txtsystem = (eventString.split(' '))[0]
    system = System.find_or_add(txtsystem)
    txttimestamp = (eventString.split(/\s+/))[1..3].join(' ')
    timestamp = (txttimestamp.split(/\s+/)[1] != "Jan" ? DateTime.parse("#{txttimestamp} 2014 GMT") : DateTime.parse("#{txttimestamp} 2015 GMT"))
    txtservice = (eventString.split(' '))[5]
    txtservice.gsub!(/[^a-zA-Z\/\-]/, "")
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
    eventString.gsub!(/[\r\n]/, "")
    eventString.gsub!(/([^a-zA-Z0-9])/," \\1 " )
    words = eventString.split(/\s+/)
    current_position = 0                  # Track which position we are at within the event
    words.each do |word|
      dbWord = Word.find_or_add(word)

      @@pendingPositionValues.push "(#{@@nextPositionID}, #{dbWord}, #{current_position}, #{@@nextEventID})"
#      position = Position.create(:word_id => dbWord.id, :position => current_position, :event_id => event.id)
      @@nextPositionID += 1
      current_position += 1
    end
    @@nextEventID += 1
    self.performPendingInserts if @@pendingEventValues.count >= 10000
  end

  def self.performPendingInserts
    return if @@pendingEventValues.count < 1
    connection = ActiveRecord::Base.connection
  
    event_sql = "INSERT INTO events (id, system_id, service_id, generated, stored) VALUES #{@@pendingEventValues.join(", ")}"
    connection.execute event_sql
  
    positions_sql = "INSERT INTO positions (id, word_id, position, event_id) VALUES #{@@pendingPositionValues.join(", ")}"
    connection.execute positions_sql
  
    @@pendingEventValues = []
    @@pendingPositionValues = []
  end
end
