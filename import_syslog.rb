#!/usr/bin/env ruby
require './config/environment.rb'

def process_logs
  Event.resetStats # reset event timing counters
  pending_logs = Dir['*'].sort
  processed = 0
  lines = 0
  begin
    pending_logs.each do |log|
      processed += 1
      puts "Processing #{log}:  Log #{processed} out of #{pending_logs.count}"
      file = File.open(log)

      file.each_line do |line|
        begin
          lines += 1
          Event.storeEvent(line)
        rescue Exception => e
          puts "Error processing #{log}!"
          puts e
          Event.performPendingInserts
          exit
        end
      end
      file.close
      File.rename(log, "../ProcessedLogs/#{log}")
    end
  rescue Interrupt
    puts "\nHalting operations... Emptying memory queues..."
    Event.performPendingInserts
  end
  Event.performPendingInserts
  Statistic.logLinesProcessed(lines)
end

def purge_logs
  # Purge logs older than 1 day ago from now.
  system("cd ../ProcessedLogs;find . -mtime +1 | xargs rm -Rf")
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