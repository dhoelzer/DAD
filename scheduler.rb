#!/usr/bin/env ruby
require './config/environment.rb'
puts $SAFE
while(true) do
  jobs = Job.where("next_run < ?", Time.now)
  jobs.each do |job|
    puts "Executing #{job.description}"
    begin
      eval(job.script)
    rescue Exception => e
      Alert.genericAlert(description: "Scheduled job failed: #{job.name} -> #{e.backtrace}", short_description: "Scheduled job failed: #{job.name}", criticality: 5)
    end
    job.next_run = Time.now + (job.frequency).seconds
    job.last_run = Time.now
    job.save
    puts "Job rescheduled for #{job.next_run}"
  end
  puts "Sleeping"
  sleep(60)
end