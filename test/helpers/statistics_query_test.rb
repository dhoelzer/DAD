require 'test_helper'

# RECOMMENDATIONS.md 3.1: the statistics helpers each issued their own copy of the
# same grouped query, and Stats.variance/standard_deviation each recomputed the mean.
# The dashboard calls these helpers several times per render and re-renders itself
# every 60 seconds.
#
# These tests pin both halves of the change: the number of round trips, and that the
# numbers themselves did not move.
class StatisticsQueryTest < ActionDispatch::IntegrationTest
  class Probe
    include ApplicationHelper
    include SystemsHelper
  end

  def setup
    @probe = Probe.new
    @system = System.create!(name: "q#{SecureRandom.hex(4)}", address: '10.0.0.1')
    @service = Service.create!(name: "qsvc#{SecureRandom.hex(4)}")
  end

  # Counts round trips whose SQL contains +pattern+.
  def count_queries(pattern)
    hits = 0
    id = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      hits += 1 if payload[:sql].to_s.include?(pattern)
    end
    yield
    ActiveSupport::Notifications.unsubscribe(id)
    hits
  end

  # Statistics in three distinct hours, with values chosen so mean, variance and
  # stddev are all non-trivial and sum is distinguishable from avg.
  def seed_statistics
    [[3, 10.0], [2, 20.0], [1, 30.0]].each do |hours_ago, stat|
      ts = hours_ago.hours.ago.beginning_of_hour + 5.minutes
      Statistic.create!(type_id: 0, stat: stat, timestamp: ts)
      Statistic.create!(type_id: 1, stat: stat * 100, timestamp: ts)
    end
  end

  def log_in
    right = Right.create!(name: 'Viewer', description: 'read')
    role = Role.create!(name: "V#{SecureRandom.hex(4)}", description: 'read')
    role.rights << right
    user = User.create!(username: "q-#{SecureRandom.hex(6)}", attempts: 0)
    user.store_password('hunter2')
    user.save!
    user.roles << role
    Preference.create!(user_id: 0, liveEventsDisplayed: 5)
    Session.create!(user: user, expiry: Time.now + 1.hour,
                    session_hash: SecureRandom.hex(16)).tap do |s|
      cookies[:sessionID] = s.session_hash
    end
  end

  # --- round trips ---

  # The template called hourly_stats twice with the same 1-day window, so the same
  # series was fetched twice per render. Four distinct series remain: type_id 0 over
  # 1 day (baseline), type_id 0 over 7 days (chart), type_id 1 over 24h (chart),
  # type_id 1 over 7 days (gauge).
  def test_dashboard_render_fetches_each_series_once
    seed_statistics
    log_in

    bucket_queries = count_queries('group by bucket') do
      get 'https://www.example.com/events.js', headers: { 'X-Requested-With' => 'XMLHttpRequest' }
    end
    assert_response :success
    assert_equal 4, bucket_queries, 'one fetch per distinct series'
  end

  def test_hourly_stats_issues_one_query
    seed_statistics
    assert_equal 1, count_queries('group by bucket') { @probe.hourly_stats(1.day.ago) }
  end

  def test_events_per_hour_issues_one_query
    seed_statistics
    assert_equal 1, count_queries('group by bucket') { @probe.events_per_hour(7.days.ago) }
  end

  def test_daily_insert_average_issues_one_query
    seed_statistics
    assert_equal 1, count_queries('group by bucket') { @probe.daily_insert_average(7.days.ago) }
  end

  # system_service_stats resolved each service with its own Service.find, i.e. one
  # query per distinct service. It is unbounded (no time window), so on a long-lived
  # install that is one query per service the host has ever reported.
  def test_system_service_stats_does_not_query_per_service
    4.times do |i|
      svc = Service.create!(name: "many#{i}#{SecureRandom.hex(3)}")
      Event.create!(system_id: @system.id, service_id: svc.id,
                    generated: 1.hour.ago, stored: Time.now, hunks: "h#{i}")
    end
    per_group = count_queries('WHERE "services"."id" =') { @probe.system_service_stats(@system.id) }
    assert_equal 0, per_group, 'must not Service.find per group'
    # one grouped count over events, plus one batched IN lookup over services
    assert_equal 1, count_queries('FROM "services"') { @probe.system_service_stats(@system.id) }
  end

  # --- values must not have moved ---

  def test_events_per_hour_values
    seed_statistics
    series = @probe.events_per_hour(7.days.ago)
    assert_equal 3, series.size
    assert_equal [10, 20, 30], series.map { |_, v| v }
  end

  def test_hourly_stats_matches_hand_computed_summary
    seed_statistics
    mean, variance, stddev = @probe.hourly_stats(3.days.ago)
    assert_in_delta 20.0, mean, 1e-9
    assert_in_delta 200.0 / 3, variance, 1e-9
    assert_in_delta Math.sqrt(200.0 / 3), stddev, 1e-9
  end

  # The old code called Stats.mean, Stats.variance and Stats.standard_deviation
  # separately, each recomputing the mean. Same numbers, fewer passes.
  def test_hourly_stats_matches_stats_module_directly
    seed_statistics
    values = @probe.hourly_buckets(0, 3.days.ago).map { |_, v| v.to_i }
    expected = [Stats.mean(values), Stats.variance(values), Stats.standard_deviation(values)]
    assert_equal expected, @probe.hourly_stats(3.days.ago)
  end

  def test_daily_insert_average_uses_sum_not_avg
    seed_statistics
    # type_id 1 stats are 1000, 2000, 3000; mean of the hourly sums, over 60.
    assert_in_delta 2000.0 / 60, @probe.daily_insert_average(7.days.ago), 1e-9
  end

  def test_inserts_per_second_uses_avg_aggregate
    seed_statistics
    assert_equal [1000.0, 2000.0, 3000.0],
                 @probe.inserts_per_second(7.days.ago).map { |_, v| v }
  end

  def test_empty_statistics_yield_zeroes_not_nan
    assert_equal [0.0, 0.0, 0.0], @probe.hourly_stats(1.day.ago)
    assert_empty @probe.events_per_hour(1.day.ago)
  end

  # --- System side ---

  def test_system_events_per_hour_values
    3.times { |i| make_event(3 - i) }
    assert_equal [1, 1, 1], @system.events_per_hour(7.days.ago).map { |_, v| v }
  end

  def test_system_hourly_stats_matches_summary_of_its_buckets
    3.times { |i| make_event(3 - i) }
    values = System.hourly_buckets(@system.id, 7.days.ago).map { |_, v| v.to_i }
    expected = [Stats.mean(values), Stats.variance(values), Stats.standard_deviation(values)]
    assert_equal expected, @system.hourly_stats(7.days.ago)
  end

  # hourly_stats filters on the exact instant, so the bucket straddling it is
  # partial. Deriving the baseline from pre-bucketed rows would lose that, so the
  # partial-hour behaviour is pinned here.
  def test_system_hourly_stats_counts_only_events_after_the_exact_instant
    base = 5.hours.ago.beginning_of_hour
    [5, 10, 20].each do |minute|
      Event.create!(system_id: @system.id, service_id: @service.id,
                    generated: base + minute.minutes, stored: Time.now, hunks: 'x')
    end
    # Only the base+20 event is after the cutoff, so the hour counts 1, not 3.
    mean, = @system.hourly_stats(base + 15.minutes)
    assert_in_delta 1.0, mean, 1e-9
    # The same hour counts all three when the window starts before it.
    full_mean, = @system.hourly_stats(base - 1.hour)
    assert_in_delta 3.0, full_mean, 1e-9
  end

  private

  def make_event(hours_ago)
    Event.create!(system_id: @system.id, service_id: @service.id,
                  generated: hours_ago.hours.ago, stored: Time.now,
                  hunks: "e#{hours_ago}")
  end
end
