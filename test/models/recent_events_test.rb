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

  # A quiet install returns fewer rows than it asked for, so growing N can
  # never help -- but the old code grew it on every poll, compounding past
  # 10% per request with no ceiling.
  test "the feed size does not grow when the table is smaller than the request" do
    seed(5, 'keep')
    10.times { Event.recent_events }
    assert_equal 10, feed_size
  end

  # With exclusions that remove most rows, growth is the intended behaviour --
  # but it has to stop somewhere. The table has to be larger than the cap,
  # otherwise the fetch stops being truncated and growth halts on its own
  # before the ceiling is reached.
  test "the feed size is capped when exclusions are noisy" do
    seed(Event::DASHBOARD_MAX_EVENTS, 'noise')
    seed(5, 'keep')
    Exclusion.create!(pattern: 'noise', user_id: 1)
    60.times { Event.recent_events }
    assert_equal Event::DASHBOARD_MAX_EVENTS, feed_size
  end

  # Guards the intended steady state: a feed that is already the right size
  # must not be nudged. (The old code called save unconditionally, but Rails
  # skips the UPDATE when nothing changed, so this held before the fix too.)
  test "the preference row is not rewritten when the size is stable" do
    seed(60, 'keep')
    Preference.where(user_id: 0).update_all(liveEventsDisplayed: 60)
    before = Preference.where(user_id: 0).first.updated_at
    Event.recent_events
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
