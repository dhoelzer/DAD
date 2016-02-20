#!/usr/bin/env ruby
require './config/environment.rb'

Event.all.each { |event| puts event.reconstitute }