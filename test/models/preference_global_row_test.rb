require 'test_helper'

# The shared user_id 0 Preference row is not created by any migration, so a fresh
# install has none. Both accessors used to call `.first.liveEventsDisplayed` on
# nil, which raised NoMethodError inside Event.recent_events and 500s the
# dashboard's /events.js poll -- leaving #graphs and #events_window permanently
# empty. The write path returned nil instead, so it discarded the setting rather
# than raising.
#
# Every other test in the suite creates the row in setup, so none of them covered
# the fresh-install case this does.
class PreferenceGlobalRowTest < ActiveSupport::TestCase
  setup do
    Preference.delete_all
  end

  test 'reading the dashboard size with no row returns the default' do
    assert_equal Preference::DEFAULT_EVENTS_DASHBOARD, Preference.eventsDashboard
  end

  # recent_events runs on GET /events.js, polled every 60s by every open tab.
  # Creating a row there would be a side effect on a GET that a proxy may replay,
  # so the fallback must be a value, not a write.
  test 'reading does not create the row' do
    Preference.eventsDashboard
    assert_equal 0, Preference.count, 'the GET path must stay side-effect free'
  end

  # A row created by hand (or by the Preferences form) can have a NULL count.
  # nil.to_i is 0, which would size the feed at zero rows and show an empty
  # dashboard with no error anywhere.
  test 'a NULL setting falls back to the default rather than zero' do
    Preference.create!(user_id: 0, liveEventsDisplayed: nil)
    assert_equal Preference::DEFAULT_EVENTS_DASHBOARD, Preference.eventsDashboard
  end

  # 0 is truthy in Ruby, so `stored || DEFAULT` would not catch this. It is the
  # worse of the two: recent_events clamps its size to a minimum of 1, then grows
  # it by configured * 0.10 -- which is 0 forever -- so the dashboard sticks at a
  # single event with no way back.
  test 'a stored zero falls back to the default' do
    Preference.create!(user_id: 0, liveEventsDisplayed: 0)
    assert_equal Preference::DEFAULT_EVENTS_DASHBOARD, Preference.eventsDashboard
  end

  # The stuck feed, end to end: with a stored 0 the feed used to return one event
  # and stay there across repeated tuning.
  test 'a stored zero does not pin the feed at one event' do
    Preference.create!(user_id: 0, liveEventsDisplayed: 0)
    system = System.create!(name: 'zero-host', address: '10.9.9.9')
    service = Service.create!(name: 'zero-svc', description: 'x')
    5.times do |i|
      Event.create!(system_id: system.id, service_id: service.id,
                    generated: Time.now - i, hunks: "zero event #{i}")
    end
    sizes = Array.new(3) { Event.recent_events.size }
    assert_operator sizes.max, :>, 1, "feed pinned at #{sizes.inspect}"
  end

  test 'a positive stored setting is honoured exactly' do
    Preference.create!(user_id: 0, liveEventsDisplayed: 12)
    assert_equal 12, Preference.eventsDashboard
  end

  test 'writing the dashboard size creates the row when none exists' do
    Preference.eventsDashboard(75)
    assert_equal 1, Preference.count
    assert_equal 75, Preference.global_row.liveEventsDisplayed
  end

  test 'writing the dashboard size reuses an existing row' do
    Preference.create!(user_id: 0, liveEventsDisplayed: 10)
    Preference.eventsDashboard(75)
    assert_equal 1, Preference.count
    assert_equal 75, Preference.eventsDashboard
  end

  # The silent half of the same bug: the write returned nil, so an operator
  # setting the archive floor on a fresh install got a success message and a
  # setting that was never stored.
  test 'writing the archive floor persists when no row exists' do
    assert_equal 25, Preference.archiveFreeSpacePercent(25)
    assert_equal 25, Preference.archiveFreeSpacePercent
    assert_equal 25, Preference.global_row.archiveFreeSpacePercent
  end

  # nil is the documented "no floor" value, so an absent row must read as nil
  # rather than raising or defaulting to a number that would enable pruning.
  test 'reading the archive floor with no row returns nil' do
    assert_nil Preference.archiveFreeSpacePercent
  end

  test 'the global row lookup does not create a row' do
    assert_nil Preference.global_row
    assert_equal 0, Preference.count
  end

  # The seeded tune_dashboard_feed job runs hourly and writes through this
  # accessor, so on a fresh install it raised every hour.
  test 'the dashboard feed tuning job works with no row' do
    summary = Event.tune_dashboard_feed_size
    assert_match(/dashboard feed size/, summary)
    assert_equal Preference::DEFAULT_EVENTS_DASHBOARD, Preference.eventsDashboard
  end

  # The read path the dashboard actually takes.
  test 'recent_events works with no row' do
    assert_kind_of Array, Event.recent_events
  end
end
