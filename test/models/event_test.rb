require 'test_helper'

class EventTest < ActiveSupport::TestCase
  setup do
    Event.resetCaches
  end

  test 'searchSQL returns placeholders only, never interpolated values' do
    sql, binds = Event.searchSQL(Time.now - 1.hour, Time.now, %w[alpha beta])
    # two range binds + one LIKE per term + the expected-term count
    assert_equal 5, sql.count('?')
    refute_includes sql, 'alpha', 'user input must not reach the SQL string'
    refute_includes sql, 'beta'
    assert_equal 1, binds.count { |_, v| v == 'alpha%' }
    assert_equal 1, binds.count { |_, v| v == 'beta%' }
    assert_equal 5, binds.size, 'two range + one per term + expected count'
  end

  test 'search treats SQL metacharacters in the query as literal text' do
    Event.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: the legitimate needle here')
    Event.performPendingInserts

    ["'; drop table events; --", "' or 1=1 --", "%' or '1'='1", "needle' --"].each do |payload|
      assert_equal [], Event.search(payload, Time.now - 1.year), "#{payload} should match nothing"
    end

    assert Event.table_exists?
    assert Event.connection.table_exists?('events_words')
    assert_equal 1, Event.search('legitimate needle', Time.now - 1.year).count
  end

  test 'search escapes LIKE wildcards in the query' do
    Event.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: uniqueword here')
    Event.performPendingInserts
    assert_equal [], Event.search('%', Time.now - 1.year)
  end

  test 'storeEvent preserves single quotes instead of rewriting them' do
    Event.storeEvent("1.1.1.1 Jun 1 00:00:00 host svc[1]: don't stop believin'")
    Event.performPendingInserts
    assert_equal "1.1.1.1 Jun 1 00:00:00 host svc[1]: don't stop believin'", Event.last.hunks
  end

  test 'storeEvent stores hostile log lines verbatim without executing them' do
    before = Event.count
    line = %q{1.1.1.1 Jun 1 00:00:00 host svc[1]: '); drop table events; --}
    Event.storeEvent(line)
    Event.performPendingInserts

    assert_equal before + 1, Event.count
    assert Event.table_exists?
    assert_equal line, Event.last.hunks
  end

  test 'insertStatement binds every value and interpolates none' do
    rows = [{ :a => 1, :b => "x'y" }, { :a => 2, :b => 'z"q' }]
    sql, binds = Event.insertStatement('tablename', %i[a b], rows)
    assert_equal 'INSERT INTO tablename (a, b) VALUES (?, ?), (?, ?)', sql
    assert_equal [[nil, 1], [nil, "x'y"], [nil, 2], [nil, 'z"q']], binds
  end

  test 'bulk inserts across several flushes all land' do
    before = Event.count
    Event.instance_variable_set(:@bulk_insert_size, 5)
    12.times do |i|
      Event.storeEvent("1.1.1.1 Jun 1 00:00:0#{i % 10} host svc[1]: bulk row #{i}")
    end
    Event.performPendingInserts
    assert_equal before + 12, Event.count
  ensure
    Event.instance_variable_set(:@bulk_insert_size, 1000)
  end
end
