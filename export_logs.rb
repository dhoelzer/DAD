#!/usr/bin/env ruby
require './config/environment.rb'

count = 0
Event.find_each do |event| 
  count = count + 1
  puts event.reconstitute
  STDERR.puts "#{ActiveSupport::NumberHelper.number_to_delimited(count)} exported..." if count % 100000 == 0
end