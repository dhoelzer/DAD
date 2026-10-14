#!/usr/bin/env ruby
require './config/environment.rb'
require './lib/log_queue.rb'

PROCESSED_DIR = '../ProcessedLogs'

# One pass over every staged log file: claims each one, feeds its lines to
# Event.storeEvent, then marks it processed.
#
# Reports progress to stdout every 50 files. On a line that raises, it flushes
# and exits the whole process rather than skipping the line, so a persistent bad
# line stops ingestion until it is removed. Ctrl-C flushes before exiting, so
# nothing already parsed is lost.
def process_logs
  Event.resetStats # reset event timing counters
  LogQueue.reclaim('.').each { |name| puts "Reclaiming abandoned #{name}" }
  logs = LogQueue.pending('.')
  processed = 0
  lines = 0
  begin
    logs.each do |log|
      processed += 1
      puts "Processing #{log}:  Log #{processed} out of #{logs.count}" if processed % 50 == 0

      # Claim before reading. If this process dies mid-file, the remainder is
      # visible as .processing and reclaimed on the next pass instead of being
      # re-read from scratch by a queue that never knew it had been started.
      in_flight = LogQueue.claim(log)

      File.foreach(in_flight) do |line|
        begin
          lines += 1
          Event.storeEvent(line)
        rescue Exception => e
          puts "Error processing #{in_flight}!"
          puts e
          puts "Offending line: #{line}"
          # Leave the file claimed: re-running it would hit the same line.
          Event.flush_and_wait
          exit 1
        end
      end
      LogQueue.complete(in_flight, PROCESSED_DIR)
    end
  rescue Interrupt
    puts "\nHalting operations... Emptying memory queues..."
    Event.flush_and_wait
    raise
  end
  Event.flush_and_wait
  Statistic.logLinesProcessed(lines)
end

# Deletes processed logs older than a day. Currently a no-op: the find/rm command is
# commented out, so ProcessedLogs accumulate indefinitely and the caller's "Purged
# logs" message is misleading.
def purge_logs
  # Purge logs older than 1 day ago from now.
  #system("cd ../ProcessedLogs;find . -mtime +1 | xargs rm -Rf")
  # -mtime +1 means modified more than 1 day ago.
end

Dir.chdir("Logs/LogsToProcess")
referenceTime = Time.now - 13.hours #force a purge when importer first runs

while true do
  process_logs
  if Time.now-12.hours > referenceTime then
    puts "Purged logs older than: #{Time.now}"
    referenceTime = Time.now
    purge_logs
  end
  sleep(1.minute)
end
