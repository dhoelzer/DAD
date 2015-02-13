#!/usr/bin/env ruby
require './config/environment.rb'

def process_logs
  pending_logs = Dir['*'].sort
  processed = 0
  begin
    pending_logs.each do |log|
      processed += 1
      puts "Processing #{log}:  Log #{processed} out of #{pending_logs.count}"
      file = File.open(log)

      file.each_line do |line|
        begin
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
  puts "Finished loop"
end

def purge_logs
  # Purge logs older than 1 day ago from now.
  system("cd ../ProcessedLogs;find . -mtime +1 | xargs rm -Rf")
end

Dir.chdir("Logs/LogsToProcess")
referenceTime = Time.now

while true do
  process_logs
  if Time.now-12.hours > referenceTime then
    puts "Purged logs older than: #{Time.now}"
    referenceTime = Time.now
    purge_logs
  end
  sleep(1.minute)
end