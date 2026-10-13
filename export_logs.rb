#!/usr/bin/env ruby
require './config/environment.rb'

# Streams every stored event back out as its original log line, one per stdout line,
# so the corpus can be replayed into another system. Progress is reported to stderr
# every 100,000 events. find_each pages by primary key, so this is safe on a table
# too large to hold in memory.
count = 0
Event.find_each do |event| 
  count = count + 1
  puts event.reconstitute
  STDERR.puts "#{ActiveSupport::NumberHelper.number_to_delimited(count)} exported..." if count % 100000 == 0
end