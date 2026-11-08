require 'test_helper'

# A Job with a nil or non-positive frequency used to save cleanly and then kill
# scheduler.rb: the reschedule line sat outside the begin/rescue, so
# `nil.seconds` raised past the rescue, out of the loop, and took the process
# down. With Restart=always and next_run never advanced, that is a permanent
# crash loop, and every other Job stops running with it.
class JobFrequencyTest < ActiveSupport::TestCase
  def job(freq)
    Job.new(name: 'x', script: 'prune_words', user_id: 1, frequency: freq)
  end

  test 'a nil frequency is rejected' do
    j = job(nil)
    refute j.valid?, 'a Job with no frequency must not save'
    assert_match(/frequency/i, j.errors.full_messages.join)
  end

  test 'a zero frequency is rejected' do
    refute job(0).valid?, 'frequency 0 would reschedule to now, running every cycle'
  end

  test 'a negative frequency is rejected' do
    refute job(-1).valid?, 'a negative frequency parks next_run in the past'
  end

  test 'clearing the frequency field does not blank a working Job' do
    existing = Job.create!(name: 'seeded', description: 'd', script: 'prune_words',
                           user_id: 1, frequency: 60, next_run: Time.now)
    existing.assign_attributes(frequency: '')
    refute existing.valid?,
      'a cleared number_field arrives as nil and must not disable the Job'
  end

  test 'a positive frequency is accepted' do
    assert job(60).valid?
  end

  test 'the scheduler cannot be handed an unusable frequency' do
    # Defence in depth: even a row written with validate: false must not be able
    # to crash a cycle (covered in job_scheduler_test).
    assert Job.column_defaults['frequency'],
      'jobs.frequency should have a database default so a nil cannot slip in'
  end
end
