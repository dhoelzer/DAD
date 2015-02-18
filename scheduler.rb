#!/usr/bin/env ruby
require './config/environment.rb'

while(true) do
  jobs = Job.where("next_run < ?", Time.now)
  jobs.each do |job|
    puts "Executing #{job.description}"
    eval(job.script)
    job.next_run = Time.now + (job.frequency).seconds
    job.save
    puts "Job rescheduled for #{job.next_run}"
  end
  puts "Sleeping"
  sleep(60)
end