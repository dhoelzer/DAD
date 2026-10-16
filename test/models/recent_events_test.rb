require 'test_helper'

# Covers Event.recent_events: the Exclusion filter and the self-tuning feed size.
#
# RECOMMENDATIONS.md §2.1 attributed an empty dashboard to Regexp.union([])
# returning /(?!)/. That regex never matches anything, so an empty Exclusion
# table filters nothing out. The empty dashboard is real, but the trigger is a
# *blank* pattern: Regexp.union([""]) is //, which matches every line.
class RecentEventsTest < ActionDispatch::IntegrationTest
  def setup
    # Fixtures contribute 2 events; keep the count explicit so the tuning
    # thresholds below are unambiguous.
    @fixture_events = Event.count
    @preference = Preference.create!(user_id: 0, liveEventsDisplayed: 10)
    @system = System.create!(name: 're-host', address: '10.7.7.7')
    @service = Service.create!(name: 're-svc', description: 'x')
  end

  def seed(count, tag)
    count.times do |i|
      Event.create!(system_id: @system.id, service_id: @service.id,
                    generated: Time.now - i,
                    hunks: "host Jun  1 12:00:00 sshd[#{i}]: #{tag} line #{i}")
    end
  end

  def feed_size
    Preference.where(user_id: 0).first.liveEventsDisplayed
  end

  # §2.1 claimed an empty Exclusion table empties the feed. It does not:
  # Regexp.union([]) => /(?!)/, which matches nothing.
  test "an empty Exclusion table filters nothing out" do
    assert_equal 0, Exclusion.count
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(20, 'keep')
    assert_equal @fixture_events + 20, Event.recent_events.count
  end

  # The actual empty-dashboard bug: a user submits the form without typing a
  # pattern, Regexp.union([""]) becomes //, and every line matches.
  test "a blank pattern does not empty the feed" do
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(20, 'keep')
    Exclusion.create!(pattern: '', user_id: 1)
    assert_equal @fixture_events + 20, Event.recent_events.count
  end

  test "a whitespace-only pattern does not empty the feed" do
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(20, 'keep')
    Exclusion.create!(pattern: '   ', user_id: 1)
    assert_equal @fixture_events + 20, Event.recent_events.count
  end

  test "a real pattern removes matching lines" do
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(10, 'keep')
    seed(5, 'noise')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    returned = Event.recent_events
    assert_equal @fixture_events + 10, returned.count
    refute(returned.any? { |line| line.include?('noise') })
  end

  # Regexp.union escapes metacharacters, so patterns are literal substrings.
  # The Exclusion model and views describe pattern as "a regex", which is
  # wrong; this test pins the behaviour until that wording is settled.
  test "patterns are matched literally, not as regexes" do
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(3, 'sshd anything fail')
    Exclusion.create!(pattern: 'sshd.*fail', user_id: 1)
    assert_equal @fixture_events + 3, Event.recent_events.count
  end

  # The read path must not write. recent_events backs GET /events and
  # GET /events.js, polled every 60s by every open dashboard tab, so it used to
  # issue an UPDATE per poll per viewer -- a GET with side effects a proxy is
  # entitled to replay. The stored size is written only by the
  # tune_dashboard_feed job.
  #
  # The noisy exclusion matters: it puts the feed under 50 rows, which is the
  # branch that *wants* to grow N. A stable feed would not have written even
  # under the old code, so it would not catch a regression.
  test "recent_events does not write to the preference row" do
    seed(60, 'keep')
    seed(200, 'noise')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    Preference.where(user_id: 0).update_all(liveEventsDisplayed: 60)
    before = Preference.where(user_id: 0).first.updated_at
    20.times { Event.recent_events }
    row = Preference.where(user_id: 0).first
    assert_equal before, row.updated_at, 'a dashboard poll must not touch the row'
    assert_equal 60, row.liveEventsDisplayed
  end

  # Same guarantee asserted the blunt way: no UPDATE statement at all.
  test "recent_events issues no writes" do
    seed(60, 'keep')
    seed(200, 'noise')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    Preference.where(user_id: 0).update_all(liveEventsDisplayed: 60)
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
      sql = payload[:sql].to_s
      writes << sql if sql.match?(/\A\s*(UPDATE|INSERT|DELETE)\b/i) && !sql.include?('sqlite_sequence')
    end
    begin
      Event.recent_events
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    assert_empty writes, "expected no writes from the read path, saw: #{writes}"
  end

  # A quiet install returns fewer rows than it asked for, so growing N can
  # never help -- but the old code grew it on every poll, compounding past
  # 10% per request with no ceiling.
  test "the feed size does not grow when the table is smaller than the request" do
    seed(5, 'keep')
    10.times { Event.recent_events }
    assert_equal 10, feed_size
    Event.tune_dashboard_feed_size
    assert_equal 10, feed_size, 'a quiet install must not climb'
  end

  # With exclusions that remove most rows, growth is the intended behaviour --
  # but it has to stop somewhere. Starts near the ceiling so the clamp, not the
  # 10% ramp, is what ends the run.
  test "the feed size is capped when exclusions are noisy" do
    seed(Event::DASHBOARD_MAX_EVENTS, 'noise')
    seed(5, 'keep')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    @preference.update_column(:liveEventsDisplayed, 500)
    Event.tune_dashboard_feed_size
    assert_equal Event::DASHBOARD_MAX_EVENTS, feed_size
  end

  # Convergence moved out of the request path and into the job: one call has to
  # settle the stored size on its own, since nothing re-runs it per poll.
  test "tune_dashboard_feed_size converges on the target in one run" do
    seed(10, 'keep')
    seed(200, 'noise')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    @preference.update_column(:liveEventsDisplayed, 50)
    summary = Event.tune_dashboard_feed_size
    tuned = feed_size
    assert_operator tuned, :>, 50, 'noisy exclusions should have grown the feed'
    # Re-tuning a settled value must be a no-op.
    Event.tune_dashboard_feed_size
    assert_equal tuned, feed_size, 'a settled feed size must not keep moving'
    assert_match(/dashboard feed size #{tuned}/, summary)
  end

  test "tune_dashboard_feed_size writes nothing when the size is already settled" do
    seed(60, 'keep')
    Preference.where(user_id: 0).update_all(liveEventsDisplayed: 60)
    before = Preference.where(user_id: 0).first.updated_at
    Event.tune_dashboard_feed_size
    assert_equal before, Preference.where(user_id: 0).first.updated_at
  end

  test "a nil hunks value does not crash the filter" do
    @preference.update_column(:liveEventsDisplayed, 100)
    seed(5, 'keep')
    Event.create!(system_id: @system.id, service_id: @service.id,
                  generated: Time.now, hunks: nil)
    Exclusion.create!(pattern: 'noise', user_id: 1)
    assert_equal @fixture_events + 5, Event.recent_events.count
  end
end
