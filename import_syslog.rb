#!/usr/bin/env ruby
require './config/environment.rb'
require './lib/log_retention.rb'

# One pass over every staged log file: feeds each line to Event.storeEvent, then
# moves the file to ../ProcessedLogs.
#
# Returns nothing but reports progress to stdout every 50 files. On a line that
# raises, it flushes the pending inserts and exits the whole process rather than
# skipping the line, so a persistent bad line stops ingestion until it is removed.
# Ctrl-C is caught: the in-memory queues are flushed before exiting the pass, so
# nothing already parsed is lost.
def process_logs
  Event.resetStats # reset event timing counters
  pending_logs = Dir['*'].sort
  processed = 0
  lines = 0
  begin
    pending_logs.each do |log|
      processed += 1
      puts "Processing #{log}:  Log #{processed} out of #{pending_logs.count}" if processed % 50 == 0

      File.foreach(log) do |line|
        begin
          lines += 1
          Event.storeEvent(line)
        rescue Exception => e
          puts "Error processing #{log}!"
          puts e
          puts "Offending line: #{line}"
          Event.performPendingInserts
          exit
        end
      end
      File.rename(log, "../ProcessedLogs/#{log}")
    end
  rescue Interrupt
    puts "\nHalting operations... Emptying memory queues..."
    Event.performPendingInserts
  end
  Event.performPendingInserts
  Statistic.logLinesProcessed(lines)
end

# Deletes processed logs older than RETENTION_DAYS. Reports what it actually
# removed: the previous version was an empty method whose caller still printed
# "Purged logs older than: ...", so the importer claimed a cleanup it never did
# while ProcessedLogs grew without bound on the same disk as the live queue.
def purge_logs
  result = LogRetention.purge(PROCESSED_LOGS, max_age: RETENTION_DAYS * 24 * 60 * 60)
  puts "Purged #{result} from #{PROCESSED_LOGS}"
end

# How long a file stays in ProcessedLogs before deletion. Keep it generous: the
# files are the only record of what was ingested, and shortening this after the
# fact cannot recover anything already deleted.
RETENTION_DAYS = 7
PROCESSED_LOGS = '../ProcessedLogs'

Dir.chdir("Logs/LogsToProcess")
referenceTime = Time.now - 13.hours #force a purge when importer first runs

while true do
  process_logs
  if Time.now-12.hours > referenceTime then
    referenceTime = Time.now
    purge_logs
  end
  sleep(1.minute)
end