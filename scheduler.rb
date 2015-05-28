#!/usr/bin/env ruby
require './config/environment.rb'
puts "The scheduler is now running.  Only errors will be displayed here."
puts $SAFE
while(true) do
  jobs = Job.where("next_run < ?", Time.now)
  jobs.each do |job|
    begin
      eval(job.script)
    rescue Exception => e
      Alert.genericAlert(description: "Scheduled job failed: #{job.name} -> #{e.backtrace}", short_description: "Scheduled job failed: #{job.name}", criticality: 5)
      puts "Error executing #{job.description}"
    end
    job.next_run = Time.now + (job.frequency).seconds
    job.last_run = Time.now
    job.save
  end
  sleep(60)
end