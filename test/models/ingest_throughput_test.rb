require 'test_helper'

# Guards the throughput figure that performPendingInserts logs and feeds to the
# @bulk_insert_size auto-tuner.
#
# The figure must be taken from the batch that was just handed off. Reading
# @@pendingEventValues after the queues are cleared yields 0, which logged a
# zero rate on every flush; the tuner then saw 0 > 0 as false and added 20 to
# @bulk_insert_size on every flush, forever.
#
# These run in-process because the bookkeeping sits outside the Rails.env.test?
# branch: both the inline and threaded write paths fall through to it.
class IngestThroughputTest < ActiveSupport::TestCase
  LINE = '1.1.1.1 Jun 1 00:00:00 host svc[1]: throughput probe'

  def setup
    EventIngestor.resetCaches
    # Above the staged count, so the explicit flush -- not storeEvent's
    # per-line flush at the dev/test default of 1 -- is what writes the batch.
    EventIngestor.bulk_insert_size = 1000
    EventIngestor.inserted_last_run = 100
    EventIngestor.resetStats
  end

  def new_rates(since_id)
    Statistic.where(type_id: 1).where('id > ?', since_id).pluck(:stat)
  end

  test 'the logged rate reflects the batch just written' do
    since = Statistic.where(type_id: 1).maximum(:id) || 0
    5.times { EventIngestor.storeEvent(LINE) }
    EventIngestor.flush_and_wait

    logged = new_rates(since)
    assert_equal 1, logged.count, 'one rate is logged per flush'
    assert_operator logged.first.to_f, :>, 0,
                    'flushing 5 events must not log a zero rate'
  end

  test 'the auto-tuner compares against a real rate' do
    5.times { EventIngestor.storeEvent(LINE) }
    EventIngestor.flush_and_wait

    assert_operator EventIngestor.inserted_last_run.to_f, :>, 0,
                    'a zero here makes every later flush take the +20 branch'
  end

  # The two fixes share these lines: batch_count must be captured before the
  # reset, and the reset must still happen before the stats bookkeeping. If the
  # reset slips back below logEventsPerSecond, a failure there leaves rows
  # staged and the next flush re-inserts them under the same explicit ids.
  test 'a failure in the stats bookkeeping does not leave rows staged' do
    3.times { EventIngestor.storeEvent(LINE) }

    Statistic.singleton_class.send(:alias_method, :log_eps_orig, :logEventsPerSecond)
    Statistic.define_singleton_method(:logEventsPerSecond) { |_rate| raise 'forced failure' }

    assert_raises(RuntimeError) { EventIngestor.performPendingInserts }
    assert_equal 0, EventIngestor.pending_count,
                 'rows already handed to the writer must not stay staged'
    assert_equal 0, EventIngestor.staged_words_count
  ensure
    Statistic.singleton_class.send(:alias_method, :logEventsPerSecond, :log_eps_orig)
  end

  # End-to-end form of the same hazard: after the forced failure above, a second
  # flush must not duplicate the ids the first one already wrote.
  test 'a flush after a stats failure does not re-insert committed ids' do
    3.times { EventIngestor.storeEvent(LINE) }
    ids = EventIngestor.pending_ids

    Statistic.singleton_class.send(:alias_method, :log_eps_orig, :logEventsPerSecond)
    Statistic.define_singleton_method(:logEventsPerSecond) { |_rate| raise 'forced failure' }
    begin
      EventIngestor.performPendingInserts
    rescue RuntimeError
      nil
    end
    Statistic.singleton_class.send(:alias_method, :logEventsPerSecond, :log_eps_orig)

    assert_equal 3, Event.where(id: ids).count,
                 'the first flush must have written its rows exactly once'
    EventIngestor.flush_and_wait
    assert_equal 3, Event.where(id: ids).count,
                 'the second flush must not re-insert them'
  end
end
