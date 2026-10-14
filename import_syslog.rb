#!/usr/bin/env ruby
require './config/environment.rb'
require './lib/log_queue.rb'
require './lib/log_retention.rb'

# How long a file stays in ProcessedLogs before deletion. Keep it generous: the
# files are the only record of what was ingested, and shortening this after the
# fact cannot recover anything already deleted.
RETENTION_DAYS = 7
PROCESSED_DIR = '../ProcessedLogs'
PURGE_INTERVAL = 12.hours

# One pass over every staged log file: claims each one, feeds its lines to
# Event.storeEvent, then marks it processed.
#
# Reports progress to stdout every 50 files. On a line that raises, it flushes
# and exits the whole process rather than skipping the line, so a persistent bad
# line stops ingestion until it is removed. Ctrl-C flushes before exiting, so
# nothing already parsed is lost.
#
# The directories are parameters rather than hardcoded so the pass can be driven
# against a temporary queue in tests.
def process_logs(queue_dir = '.', processed_dir = PROCESSED_DIR)
  Event.resetStats # reset event timing counters
  LogQueue.reclaim(queue_dir).each { |name| puts "Reclaiming abandoned #{name}" }
  logs = LogQueue.pending(queue_dir)
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
      LogQueue.complete(in_flight, processed_dir)
    end
  rescue Interrupt
    puts "\nHalting operations... Emptying memory queues..."
    Event.flush_and_wait
    raise
  end
  Event.flush_and_wait
  Statistic.logLinesProcessed(lines)
  lines
end

# Deletes processed logs older than RETENTION_DAYS. Reports what it actually
# removed: the previous version was an empty method whose caller still printed
# "Purged logs older than: ...", so the importer claimed a cleanup it never did
# while ProcessedLogs grew without bound on the same disk as the live queue.
def purge_logs(processed_dir = PROCESSED_DIR)
  purged = LogRetention.purge(processed_dir, max_age: RETENTION_DAYS * 24 * 60 * 60)
  puts "Purged #{purged} from #{processed_dir}"
  purged
end

# The loop only runs when the script is executed directly. Requiring the file --
# which the tests do -- defines the methods without chdir-ing the process or
# starting a second importer.
if __FILE__ == $PROGRAM_NAME
  Dir.chdir('Logs/LogsToProcess')
  # Backdate the marker so the first pass purges, catching anything left over
  # from a previous run.
  reference_time = Time.now - (PURGE_INTERVAL + 1.hour)

  loop do
    process_logs
    if Time.now - PURGE_INTERVAL > reference_time
      reference_time = Time.now
      purge_logs
    end
    sleep 1.minute
  end
end
