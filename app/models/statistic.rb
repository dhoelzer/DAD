class Statistic < ActiveRecord::Base

  def self.logLinesProcessed(lines)
    statistic = Statistic.new
    statistic.type_id = 0
    statistic.system_id = -1
    statistic.service_id = -1
    statistic.stat = lines
    statistic.timestamp = Time.now
    statistic.save
  end

  def self.logEventsPerSecond(eventsPerSecond)
    statistic = Statistic.new
    statistic.type_id = 1
    statistic.system_id = -1
    statistic.service_id = -1
    statistic.stat = eventsPerSecond
    statistic.timestamp = Time.now
    statistic.save
  end

  def self.hidden?
    return true
  end
  
end
