# One pass of the job scheduler: run every Job whose next_run has passed.
#
# scheduler.rb is the loop; this is the body, extracted so the loop body can be
# tested. It previously lived inline in a `while(true)`, which is why nothing
# covered it and why a crash in the reschedule step survived every previous
# change to this file.
#
# The invariant this exists to protect: no single Job row can stop any other Job
# from running, and none can take the process down. scheduler.rb runs under
# Restart=always, so an escaping exception is a crash loop, and because the
# crashing row's next_run never advances it is re-selected immediately on every
# restart.
class JobScheduler
  # Runs every due Job exactly once.
  def self.run_cycle
    Job.where('next_run < ?', Time.now).find_each { |job| run_job(job) }
  end

  def self.run_job(job)
    begin
      Rails.logger.info "job #{job.name} -> #{JobHandler.perform(job.script)}"
    rescue Exception => e
      # A handler that raises is a fault in one Job, not in the scheduler.
      Alert.genericAlert(
        description: "Scheduled job failed: #{job.name} -> #{e.backtrace}",
        short_description: "Scheduled job failed: #{job.name}",
        criticality: 5)
      Rails.logger.error "Error executing #{job.description}"
    end
    reschedule(job)
  end

  # Advances next_run so the Job is not re-selected until its interval elapses.
  #
  # This step used to sit outside the rescue in scheduler.rb, so a Job whose
  # frequency could not produce an interval raised here, past the rescue, out of
  # the loop, and out of the process -- taking every later Job in the cycle with
  # it. A blank "Frequency" field in the job form was enough to cause it.
  #
  # A row with no usable interval is disarmed rather than skipped: next_run goes
  # NULL, which the `next_run < ?` predicate never matches, so it stops being
  # selected at all. That is the same convention the retire_legacy_job_scripts
  # migration uses, and it is what keeps a broken row from alerting once a minute
  # forever. An operator fixes the interval and re-enables it deliberately.
  def self.reschedule(job)
    frequency = job.frequency
    if frequency.nil? || frequency.to_i <= 0
      Alert.genericAlert(
        description: "Scheduled job #{job.name} has no usable frequency " \
                     '(nil or non-positive); it has been disabled. Set a positive ' \
                     'interval to re-enable it.',
        short_description: "Scheduled job disabled: #{job.name}",
        criticality: 5)
      Rails.logger.error "Disabling job #{job.name}: unusable frequency #{frequency.inspect}"
      job.next_run = nil
      # validate: false on purpose. The row is already invalid -- that is the
      # problem being handled -- so a validating save would silently fail and
      # leave next_run in the past, re-selecting the row every cycle.
      job.save(validate: false)
      return
    end

    job.next_run = Time.now + frequency.to_i.seconds
    job.last_run = Time.now
    job.save
  end
end
