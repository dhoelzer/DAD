require 'test_helper'

# Guards the placeholder translation that lets one hand-written query run on both
# SQLite (dev/test) and Postgres (production).
#
# The bug this covers was total, not subtle: Event.insertStatement emitted SQLite
# `?` placeholders through exec_query, Postgres rejected them with a syntax error,
# and production therefore could not insert a single event -- while the whole suite
# stayed green because it only ever runs SQLite.
#
# The call-site tests below are written to pass on either adapter, so a Postgres CI
# run exercises the same assertions against the engine that actually broke. The
# pure rewriting tests pin the rules on whichever engine the run uses.
class SqlPlaceholdersTest < ActiveSupport::TestCase
  # --- the rewriting rules, adapter-independent ---

  test 'numbers placeholders left to right' do
    assert_equal 'select * from t where a = $1 and b = $2',
      SqlPlaceholders.number_placeholders('select * from t where a = ? and b = ?')
  end

  test 'numbers every placeholder in a multi-row insert' do
    # The shape Event.insertStatement builds: one group per row, cumulative numbering.
    assert_equal 'INSERT INTO t (a, b) VALUES ($1, $2), ($3, $4)',
      SqlPlaceholders.number_placeholders('INSERT INTO t (a, b) VALUES (?, ?), (?, ?)')
  end

  test 'leaves a query with no placeholders alone' do
    assert_equal 'select count(*) from t',
      SqlPlaceholders.number_placeholders('select count(*) from t')
  end

  # A LIKE pattern is data. Rewriting the ? inside it both corrupts the pattern and
  # shifts the numbering of every real placeholder that follows.
  test 'does not rewrite a question mark inside a string literal' do
    assert_equal "select * from t where text like 'a?b' and id = $1",
      SqlPlaceholders.number_placeholders("select * from t where text like 'a?b' and id = ?")
  end

  test 'does not rewrite a question mark inside a quoted identifier' do
    assert_equal 'select "we?ird" from t where id = $1',
      SqlPlaceholders.number_placeholders('select "we?ird" from t where id = ?')
  end

  # '' is an embedded quote, so the literal continues past it and the ? is still data.
  test 'handles an escaped quote inside a literal' do
    assert_equal "select * from t where text = 'it''s?' and id = $1",
      SqlPlaceholders.number_placeholders("select * from t where text = 'it''s?' and id = ?")
  end

  # --- the query path, on whichever adapter this run uses ---

  # The point of the helper: the same SQL text and the same bind array must work on
  # both engines. Asserting the returned rows proves the binds landed in the right
  # slots, not merely that the statement parsed.
  test 'query binds values in order and returns the right rows' do
    lo = System.create!(name: 'sqlph_lo', address: '10.200.0.1')
    hi = System.create!(name: 'sqlph_hi', address: '10.200.0.2')

    # Upper bound stays inside int4: the original migrations declare systems.id as
    # `id: :integer`, so a bigint sentinel binds fine on SQLite but Postgres
    # rejects it as out of range for the inferred parameter type.
    both = SqlPlaceholders.query(
      'select count(*) as c from systems where id > ? and id < ?',
      [0, 2_000_000_000]
    )[0]['c'].to_i
    assert_operator both, :>=, 2

    between = SqlPlaceholders.query(
      'select count(*) as c from systems where id > ? and id < ?',
      [lo.id, hi.id]
    )[0]['c'].to_i
    assert_equal 0, between, 'the range strictly between the two ids holds no rows'

    named = SqlPlaceholders.query('select name from systems where id = ?', [hi.id])[0]['name']
    assert_equal 'sqlph_hi', named, 'binds must land in the slots they appear in'
  end

  test 'query passes a single bind through unchanged' do
    row = SqlPlaceholders.query('select ? as picked', ['only'])[0]
    assert_equal 'only', row['picked']
  end

  # --- the production call sites, on whichever adapter this run uses ---

  # All four of these went through exec_query with `?` and raised PG::SyntaxError on
  # Postgres. They are the methods the dashboard and the reports actually call.
  test 'System.reportingInLastDays runs and counts per system' do
    system = new_system_with_events('sqlph_report', '10.200.0.3', 3)

    rows = System.reportingInLastDays(7).to_a
    found = rows.find { |r| r['system_id'] == system.id }
    refute_nil found, 'the system should appear in the report'
    assert_equal 3, found['count'].to_i
  end

  test 'System.hourly_counts buckets events by hour' do
    system = new_system_with_events('sqlph_hourly', '10.200.0.4', 4)

    rows = System.hourly_counts(system.id, 2.days.ago).to_a
    assert_equal 1, rows.size, 'all four events fall in one hour'
    assert_equal 4, rows[0]['count'].to_i
  end

  test 'System#events_since counts with two binds' do
    system = new_system_with_events('sqlph_since', '10.200.0.5', 5)

    assert_equal 5, system.events_since(2.days.ago)
    assert_equal 0, system.events_since(2.days.from_now)
  end

  test 'statistics_by_hour aggregates with two binds' do
    3.times { Statistic.create!(type_id: 7, stat: 10.0, timestamp: Time.now) }

    rows = ApplicationController.helpers.statistics_by_hour(7, 2.days.ago).to_a
    assert_equal 1, rows.size
    assert_in_delta 30.0, rows[0]['agg_value'].to_f, 0.001
  end

  # The ingest path itself: insertStatement builds both bulk INSERTs, and this is the
  # code production runs for every line it imports. This is the assertion that would
  # have caught the original bug on a Postgres run.
  test 'bulk ingest writes events and their index rows' do
    Event.resetCaches
    3.times { |i| Event.storeEvent("10.200.0.6 Jun 1 12:00:0#{i} host svc[1]: placeholder probe #{i}") }
    Event.flush_and_wait

    system = System.find_by(address: '10.200.0.6')
    refute_nil system, 'ingest must resolve the system from the line'
    assert_equal 3, Event.where(system_id: system.id).count, 'every staged event must be written'

    # events_words is written first in the same transaction; an event with no index
    # row is invisible to search.
    indexed = SqlPlaceholders.query(
      'select count(*) as c from events_words where event_id in (select id from events where system_id = ?)',
      [system.id]
    )[0]['c'].to_i
    assert_operator indexed, :>, 0, 'each event must have word index rows'

    orphans = SqlPlaceholders.query(
      'select count(*) as c from events_words where event_id not in (select id from events)'
    )[0]['c'].to_i
    assert_equal 0, orphans, 'no index row may point at a missing event'
  end

  def new_system_with_events(name, address, count)
    system = System.create!(name: name, address: address)
    service = Service.create!(name: "sqlph_#{name}")
    count.times do
      Event.create!(system_id: system.id, service_id: service.id,
                    generated: Time.now, stored: Time.now)
    end
    system
  end
end
