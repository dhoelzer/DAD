require 'test_helper'

# Dashboard aggregation helpers and the authorisation lookup.
#
# These were N+1: system_stats/service_stats issued one find per group, and
# System.with_events_within_hours did the same on every dashboard poll. The
# helpers were also where a display-name collision silently dropped a count,
# because results were keyed by name rather than by id.
class DashboardStatsTest < ActionView::TestCase
  include ApplicationHelper

  def setup
    # Same name, different address: display_name derives from name, so these
    # two hosts collide as chart labels.
    @system_a = System.create!(name: 'shared-name', address: '10.7.1.1')
    @system_b = System.create!(name: 'shared-name', address: '10.7.1.2')
    @service_a = Service.create!(name: 'n1-svc-a', description: 'x')
    @service_b = Service.create!(name: 'n1-svc-b', description: 'x')
    now = Time.now
    [[@system_a, @service_a, 3], [@system_b, @service_b, 2]].each do |sys, svc, n|
      n.times do |i|
        Event.create!(system_id: sys.id, service_id: svc.id, generated: now - i,
                      hunks: "host Jun  1 12:00:00 n1probe[#{i}]: #{sys.address} #{svc.name} line #{i}")
      end
    end
  end

  def with_query_capture
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*_args, payload|
      next if payload[:name] == 'SCHEMA'
      sql = payload[:sql]
      next if sql =~ /\A\s*(BEGIN|COMMIT|ROLLBACK|PRAGMA|SAVEPOINT|RELEASE)/i
      queries << sql
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test 'system_stats issues one grouped count plus one lookup, not one find per group' do
    queries = with_query_capture { system_stats(10) }
    grouped = queries.select { |q| q =~ /GROUP BY.*system_id/i }
    lookups = queries.select { |q| q =~ /FROM "systems"/i }
    assert_equal 1, grouped.size, "expected one grouped count: #{queries.inspect}"
    assert_equal 1, lookups.size,
      "expected a single systems lookup for all ids, got #{lookups.size}: #{lookups.inspect}"
  end

  test 'system_stats returns one entry per system, even when names collide' do
    result = system_stats(10)
    mine = result.select { |name, _| name == 'shared-name' }
    assert_equal 2, mine.size,
      'two hosts sharing a display name must not collapse into one entry'
    assert_equal [3, 2], mine.map(&:last).sort.reverse
  end

  test 'service_stats issues one grouped count plus one lookup' do
    queries = with_query_capture { service_stats(10) }
    lookups = queries.select { |q| q =~ /FROM "services"/i }
    assert_equal 1, lookups.size,
      "expected a single services lookup for all ids, got #{lookups.size}: #{lookups.inspect}"
  end

  test 'with_events_within_hours issues two queries regardless of host count' do
    queries = with_query_capture { System.with_events_within_hours(10) }
    assert_equal 2, queries.size, "expected 2 queries, got: #{queries.inspect}"
  end

  test 'with_events_within_hours returns reporting systems only' do
    reporting = System.where(id: [@system_a.id, @system_b.id])
    assert_equal reporting.to_a.sort_by(&:id), System.with_events_within_hours(10).sort_by(&:id)
    assert_empty (System.with_events_within_hours(1) - reporting.to_a),
      'a system with no events in the window must not appear'
  end
end
