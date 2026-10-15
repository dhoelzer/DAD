require 'test_helper'

class EventTest < ActiveSupport::TestCase
  setup do
    Event.resetCaches
  end

  # three binds per term (range lower, range upper, LIKE pattern) in both the
  # WHERE and the HAVING subqueries, plus the range and the expected count
  PLACEHOLDERS_PER_TERM = 6

  test 'searchSQL returns placeholders only, never interpolated values' do
    terms = %w[alpha beta]
    sql, binds = Event.searchSQL(Time.now - 1.hour, Time.now, terms)
    expected = terms.size * PLACEHOLDERS_PER_TERM + 3
    assert_equal expected, sql.count('?')
    refute_includes sql, 'alpha', 'user input must not reach the SQL string'
    refute_includes sql, 'beta'
    assert_equal expected, binds.size
    assert_equal 2, binds.count { |v| v == 'alpha%' }
    assert_equal 2, binds.count { |v| v == 'beta%' }
    assert_equal terms.size, binds.last
  end

  test 'searchSQL restricts events_words on word_id so the covering index applies' do
    sql, = Event.searchSQL(Time.now - 1.hour, Time.now, %w[alpha])
    assert_includes sql, 'events_words.word_id in (select id from words'
    refute_includes sql, 'inner join words',
      'joining words forces a full scan of events_words through the generated index'
  end

  test 'the search covering index exists' do
    assert Event.connection.index_exists?(:events_words, %w[word_id generated event_id],
      name: 'index_events_words_on_word_id_and_generated_and_event_id')
  end

  test 'search uses the covering index rather than scanning events_words' do
    skip 'plan check is sqlite-specific' unless Event.connection.adapter_name == 'SQLite'
    sql, binds = Event.searchSQL(Time.now - 1.year, Time.now, %w[failed connection])
    plan = Event.connection.execute('EXPLAIN QUERY PLAN ' +
      ActiveRecord::Base.send(:sanitize_sql_array, [sql, *binds])).map { |r| r['detail'] }.join("\n")
    assert_includes plan, 'USING COVERING INDEX index_events_words_on_word_id_and_generated_and_event_id'
    refute_match(/SCAN events_words/, plan)
  end

  # storeEvent's tokenizer keeps a-zA-Z0-9 and " -_:@*/." and blanks everything
  # else, so those punctuation characters are the ones that can appear in a word
  # and must be matched literally rather than as LIKE wildcards.
  test 'search matches LIKE wildcards literally in words' do
    %w[foo_bar fooXbar a-b ab 10.0.1.5 10x0x1x5].each do |w|
      Event.storeEvent("1.1.1.1 Jun 1 00:00:00 host svc[1]: #{w}")
    end
    Event.performPendingInserts

    assert_equal 1, Event.search('foo_bar', Time.now - 1.year).count,
      '_ must not act as a single-character wildcard'
    assert_equal 1, Event.search('a-b', Time.now - 1.year).count
    assert_equal 1, Event.search('10.0.1.5', Time.now - 1.year).count
    assert_equal 0, Event.search('10.0.1.5x', Time.now - 1.year).count

    # 'ab' must match the event holding the word 'ab' and not the one holding
    # 'a-b': a range-only prefix filter would wrongly include a-b under a
    # punctuation-insensitive collation such as PostgreSQL's en_US.UTF-8.
    ab = Event.search('ab', Time.now - 1.year)
    assert_equal 1, ab.count
    assert_includes ab.first.hunks.split(/\s+/), 'ab'
    refute_includes ab.first.hunks.split(/\s+/), 'a-b'
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
    assert_equal [1, "x'y", 2, 'z"q'], binds
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
