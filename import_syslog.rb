#!/usr/bin/env ruby
require './config/environment.rb'

Dir['Logs/LogsToProcess/*'].each do |log|
  file = File.open(log)
  file.each_line do |line|
    Event.storeEvent(line)
  end
  print "There were #{Word.number_of_cached_words} words cached and there are #{Word.count} words total.  #{Word.added} words were added.\n"
    # move log
end
Event.performPendingInserts