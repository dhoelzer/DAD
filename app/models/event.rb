class Event < ActiveRecord::Base
  has_many :positions
  has_many :words, :through => :positions
  belongs_to :system
  belongs_to :service
  
  def self.storeEvent(eventString)
    txtsystem = (eventString.split(' '))[4]
    system = System.find_or_add(txtsystem)
    txttimestamp = (eventString.split(' '))[1..3].join(' ')
    timestamp = DateTime.parse("#{txttimestamp} UTC")
    txtservice = (eventString.split(' '))[5]
    txtservice.gsub!(/[^a-zA-Z\/\-]/, "")
    service = Service.find_or_add(txtservice)

    event = Event.create(:system_id => system.id, :service_id => service.id, :generated => timestamp, :stored => Time.now)
    return nil if event.nil?

    eventString.downcase!
    eventString.gsub!(/[\r\n]/, "")
    eventString.gsub!(/([^a-zA-Z0-9])/," \\1 " )
    words = eventString.split(/\s+/)
    current_position = 0                  # Track which position we are at within the event
    words.each do |word|
      dbWord = Word.find_or_add(word)
      #TODO: I feel like this next line should be refactored into Position.
      position = Position.create(:word_id => dbWord.id, :position => current_position, :event_id => event.id)
      current_position += 1
    end
  end
end
