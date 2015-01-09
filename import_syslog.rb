#!/usr/bin/env ruby
require './config/environment.rb'

pending_logs = Dir['Logs/LogsToProcess/*'].sort
processed = 0
pending_logs.each do |log|
  processed += 1
  puts "Processing #{log}:  Log #{processed} out of #{pending_logs.count}"
  file = File.open(log)
  file.each_line do |line|
    Event.storeEvent(line)
  end
  print ">>> There are #{Word.number_of_cached_words} words currently cached and there are #{Word.count} words total.  #{Word.added} words were added.\n"
    # move log
end
Event.performPendingInserts