#!/usr/bin/env ruby
require './config/environment.rb'

# See the note in import_syslog.rb: a service that only writes to
# log/<env>.log is invisible to its supervisor.
Rails.logger = ActiveSupport::BroadcastLogger.new(
  Rails.logger, ActiveSupport::Logger.new($stdout))

Rails.logger.info 'The scheduler is now running.  Only errors will be displayed here.'

# Main loop: every 60 seconds, run each Job whose next_run has passed. The work
# itself lives in JobScheduler.run_cycle, which is where the per-Job isolation is
# guaranteed and where the tests are.
#
# Job#script names an entry in the JobHandler::HANDLERS registry, so a Job can
# only do something the code already supports -- no user-authored Ruby is
# evaluated here (RECOMMENDATIONS.md 1.2). A failing handler is rescued, reported
# as a Critical Alert, and the Job is still rescheduled; a permanently broken Job
# therefore raises an Alert on every cycle forever.
while(true) do
  begin
    JobScheduler.run_cycle
  rescue Exception => e
    # Last line of defence. run_cycle already isolates each Job, so reaching
    # here means something outside the per-Job path failed -- the query itself,
    # or a bug in the loop. Logging and continuing keeps the other Jobs alive;
    # letting it escape means Restart=always plus a crash loop, because the
    # crashing Job's next_run never advances and it is re-selected immediately.
    Rails.logger.error "Scheduler cycle failed: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
  end
  sleep(60)
end