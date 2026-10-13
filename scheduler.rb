#!/usr/bin/env ruby
require './config/environment.rb'
puts "The scheduler is now running.  Only errors will be displayed here."
puts $SAFE
# Main loop: every 60 seconds, run each Job whose next_run has passed.
#
# Job#script names an entry in the JobHandler::HANDLERS registry, so a Job can
# only do something the code already supports -- no user-authored Ruby is
# evaluated here (RECOMMENDATIONS.md 1.2). A failing handler is rescued, reported
# as a Critical Alert, and the job is still rescheduled; a permanently broken Job
# therefore raises an Alert on every cycle forever.
while(true) do
  jobs = Job.where("next_run < ?", Time.now)
  jobs.each do |job|
    begin
      puts "#{Time.now}: job #{job.name} -> #{JobHandler.perform(job.script)}"
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