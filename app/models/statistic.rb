# A time-series sample written by the ingestion pipeline and charted on the
# dashboard. +type_id+ selects the series: 0 = lines processed, 1 = events/sec.
#
# Rows are append-only; nothing in the app updates or deletes them.
class Statistic < ActiveRecord::Base

  # Records that +lines+ log lines were processed in this importer pass
  # (type_id 0). Called once per pass by import_syslog.rb.
  def self.logLinesProcessed(lines)
    statistic = Statistic.new
    statistic.type_id = 0
    statistic.system_id = -1
    statistic.service_id = -1
    statistic.stat = lines
    statistic.timestamp = Time.now
    statistic.save
  end

  # Records an insert rate of +eventsPerSecond+ for this flush (type_id 1).
  #
  # Called by Event.performPendingInserts after each batch. system_id/service_id
  # are -1 because the sample is global, not per-system.
  def self.logEventsPerSecond(eventsPerSecond)
    statistic = Statistic.new
    statistic.type_id = 1
    statistic.system_id = -1
    statistic.service_id = -1
    statistic.stat = eventsPerSecond
    statistic.timestamp = Time.now
    statistic.save
  end

  # Statistics are rendered on the dashboard, not as their own index page.
  def self.hidden?(current_user = nil)
    return true
  end

end
