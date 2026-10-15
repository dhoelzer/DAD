# A time-series sample written by the ingestion pipeline and charted on the
# dashboard.
#
# Rows are append-only; nothing in the app updates or deletes them.
#
# type_id selects the series. The values are magic numbers baked into existing
# rows and into the dashboard queries, so a series can be added but never
# renumbered:
#   0 = lines processed per importer pass
#   1 = events/sec per flush
#   2 = log lines skipped as unprocessable, per importer pass
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

  # Records that +failures+ log lines were skipped as unprocessable in this
  # importer pass (type_id 2).
  #
  # The count exists because skipping is the price of not dying: a line that
  # raises is logged and passed over so one bad record cannot stop ingestion
  # (§5.3). Without a counter, "the importer is fine" and "the importer is
  # silently discarding everything" look identical from the outside.
  def self.logLineFailures(failures)
    statistic = Statistic.new
    statistic.type_id = 2
    statistic.system_id = -1
    statistic.service_id = -1
    statistic.stat = failures
    statistic.timestamp = Time.now
    statistic.save
  end

  # Statistics are rendered on the dashboard, not as their own index page.
  def self.hidden?(current_user = nil)
    return true
  end

end
