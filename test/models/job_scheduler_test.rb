require 'test_helper'

# scheduler.rb ran the handler inside begin/rescue but the reschedule line
# outside it. A Job that could not be rescheduled therefore raised past the
# rescue and out of the loop, stopping every other Job in the same cycle and
# then the process. These tests drive the extracted cycle rather than the
# `while(true)` wrapper, so the loop body is actually under test.
class JobSchedulerTest < ActiveSupport::TestCase
  def setup
    Job.delete_all
  end

  # Runs the real JobScheduler with JobHandler.perform swapped for one that
  # raises for +script+ only. HANDLERS is frozen on purpose, so the seam is the
  # dispatcher rather than the registry.
  def with_failing_handler(script)
    original = JobHandler.method(:perform)
    JobHandler.define_singleton_method(:perform) do |name, arg = nil|
      raise 'handler exploded' if name.to_s == script
      original.call(name, arg)
    end
    yield
  ensure
    JobHandler.define_singleton_method(:perform, original)
  end

  # The core regression: a poison row must not stop a healthy Job.
  test 'a Job that cannot be rescheduled does not stop the others' do
    poison = Job.new(name: 'poison', description: 'd', script: 'prune_words',
                     user_id: 1, frequency: nil, next_run: Time.now - 10)
    poison.save!(validate: false)
    healthy = Job.create!(name: 'healthy', description: 'd', script: 'reset_stats',
                          user_id: 1, frequency: 60, next_run: Time.now - 10)

    JobScheduler.run_cycle

    assert healthy.reload.next_run > Time.now,
      'a healthy Job must still run and reschedule when an earlier row is broken'
  end

  test 'a Job whose handler raises is still rescheduled' do
    broken = Job.create!(name: 'broken', description: 'd', script: 'prune_words',
                         user_id: 1, frequency: 60, next_run: Time.now - 10)
    healthy = Job.create!(name: 'healthy', description: 'd', script: 'reset_stats',
                          user_id: 1, frequency: 60, next_run: Time.now - 10)

    with_failing_handler('prune_words') { JobScheduler.run_cycle }

    assert healthy.reload.next_run > Time.now, 'the healthy Job must be rescheduled'
    assert broken.reload.next_run > Time.now,
      'a failing Job must be rescheduled too, so it retries on its own interval ' \
      'instead of being re-selected every 60 seconds forever'
  end

  test 'a failing Job raises an Alert' do
    Job.create!(name: 'boom', description: 'd', script: 'prune_words',
                user_id: 1, frequency: 60, next_run: Time.now - 10)
    before = Alert.count
    with_failing_handler('prune_words') { JobScheduler.run_cycle }
    assert_operator Alert.count, :>, before, 'a failed Job must still alert'
  end

  # The retire_legacy_job_scripts migration makes a Job inert by clearing script
  # AND setting next_run NULL, so it is never selected. If a row somehow has a
  # due next_run but no script, the right outcome is an Alert and a reschedule,
  # not a crash that stops the rest of the cycle.
  test 'a Job with no script alerts and reschedules rather than crashing the cycle' do
    retired = Job.new(name: 'retired', description: 'd', script: nil,
                      user_id: 1, frequency: 60, next_run: Time.now - 10)
    retired.save!(validate: false)
    healthy = Job.create!(name: 'healthy', description: 'd', script: 'reset_stats',
                          user_id: 1, frequency: 60, next_run: Time.now - 10)

    JobScheduler.run_cycle

    assert healthy.reload.next_run > Time.now, 'the healthy Job must still run'
    assert retired.reload.next_run > Time.now, 'the script-less Job must be rescheduled'
  end

  test 'a Job whose next_run is null is never selected' do
    retired = Job.create!(name: 'retired', description: 'd', script: 'prune_words',
                          user_id: 1, frequency: 60, next_run: nil)
    JobScheduler.run_cycle
    assert_nil retired.reload.next_run
  end

  test 'a Job scheduled for the future is not run' do
    future = Job.create!(name: 'future', description: 'd', script: 'reset_stats',
                         user_id: 1, frequency: 60, next_run: Time.now + 3600)
    before = future.next_run
    JobScheduler.run_cycle
    assert_equal before.to_i, future.reload.next_run.to_i
  end
end
