require 'test_helper'

class EventTest < ActiveSupport::TestCase
  setup do
    EventIngestor.resetCaches
  end

  # Binds per term: SQLite narrows the words lookup with a byte-wise range
  # (lower bound, upper bound, LIKE pattern), Postgres matches on the LIKE alone.
  # Plus the time range and the expected term count. Each term is bound once: the
  # derived table resolves it a single time, so the count scales with terms, not
  # with terms*2.
  def placeholders_per_term
    Event.connection.adapter_name == 'SQLite' ? 3 : 1
  end

  test 'searchSQL returns placeholders only, never interpolated values' do
    terms = %w[alpha beta]
    sql, binds = Event.searchSQL(Time.now - 1.hour, Time.now, terms)
    expected = terms.size * placeholders_per_term + 3
    assert_equal expected, sql.count('?')
    refute_includes sql, 'alpha', 'user input must not reach the SQL string'
    refute_includes sql, 'beta'
    assert_equal expected, binds.size
    assert_equal 1, binds.count { |v| v == 'alpha%' }, 'each term resolves its word set once'
    assert_equal 1, binds.count { |v| v == 'beta%' }
    assert_equal terms.size, binds.last
  end

  test 'searchSQL restricts events_words on word_id so the covering index applies' do
    sql, = Event.searchSQL(Time.now - 1.hour, Time.now, %w[alpha])
    assert_includes sql, 'terms on terms.word_id = events_words.word_id'
    assert_includes sql, 'select id as word_id, 1 as term_no from (select id from words'
    refute_includes sql, 'join words',
      'joining words directly forces a full scan of events_words through the generated index'
  end

  test 'the search covering index exists' do
    assert Event.connection.index_exists?(:events_words, %w[word_id generated event_id],
      name: 'index_events_words_on_word_id_and_generated_and_event_id')
  end

  # Postgres needs a byte-wise index for the prefix LIKE: a plain index on
  # words.text is ordered by the database collation, and under en_US.UTF-8 the
  # planner can only seq scan it.
  test 'the byte-wise words index exists on Postgres' do
    skip 'the pattern index is Postgres-only' unless Event.connection.adapter_name == 'PostgreSQL'
    assert Event.connection.index_exists?(:words, :text, name: 'index_words_on_text_pattern')
  end

  # The Postgres words lookup must not carry an upper bound. [term, term +
  # U+10FFFF) is only sound for byte-wise collations: under en_US.UTF-8 strcoll
  # sorts U+10FFFF before ASCII letters, so the bound sits below every longer
  # word and prefix search silently returns nothing. See the WORD_IDS_BYTEWISE comment.
  test 'the Postgres words lookup puts no upper bound on the range' do
    skip 'SQLite orders text byte-wise, where the range is sound' unless
      Event.connection.adapter_name == 'PostgreSQL'
    sql, = Event.searchSQL(Time.now - 1.hour, Time.now, %w[alpha])
    refute_match(/text\s*</, sql,
      'no finite upper bound is sound for a punctuation-terminated prefix under a punctuation-insensitive collation')
  end

  # Direct guard for the collation bug: a term that is a strict prefix of an
  # indexed word must match it. This passed on SQLite (BINARY) and on a Postgres
  # cluster initialised with C.UTF-8, and failed on the en_US.UTF-8 that CI and
  # provisioned production use.
  test 'prefix search matches words longer than the term' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: testservice reports')
    EventIngestor.performPendingInserts

    %w[test testservice testse].each do |term|
      assert_equal 1, Event.search(term, (Time.now - 1.year)..Time.now).count,
        "#{term} must match the word testservice"
    end
    assert_equal [], Event.search('service', (Time.now - 1.year)..Time.now),
      'matching is prefix-only, not substring'
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
      EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:00 host svc[1]: #{w}")
    end
    EventIngestor.performPendingInserts

    assert_equal 1, Event.search('foo_bar', (Time.now - 1.year)..Time.now).count,
      '_ must not act as a single-character wildcard'
    assert_equal 1, Event.search('a-b', (Time.now - 1.year)..Time.now).count
    assert_equal 1, Event.search('10.0.1.5', (Time.now - 1.year)..Time.now).count
    assert_equal 0, Event.search('10.0.1.5x', (Time.now - 1.year)..Time.now).count

    # 'ab' must match the event holding the word 'ab' and not the one holding
    # 'a-b': a range-only prefix filter would wrongly include a-b under a
    # punctuation-insensitive collation such as PostgreSQL's en_US.UTF-8.
    ab = Event.search('ab', (Time.now - 1.year)..Time.now)
    assert_equal 1, ab.count
    assert_includes ab.first.hunks.split(/\s+/), 'ab'
    refute_includes ab.first.hunks.split(/\s+/), 'a-b'
  end

  test 'search treats SQL metacharacters in the query as literal text' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: the legitimate needle here')
    EventIngestor.performPendingInserts

    ["'; drop table events; --", "' or 1=1 --", "%' or '1'='1", "needle' --"].each do |payload|
      assert_equal [], Event.search(payload, (Time.now - 1.year)..Time.now), "#{payload} should match nothing"
    end

    assert Event.table_exists?
    assert Event.connection.table_exists?('events_words')
    assert_equal 1, Event.search('legitimate needle', (Time.now - 1.year)..Time.now).count
  end

  test 'search escapes LIKE wildcards in the query' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: uniqueword here')
    EventIngestor.performPendingInserts
    assert_equal [], Event.search('%', (Time.now - 1.year)..Time.now)
  end

  # The search is relational division: an event matches only when its words cover
  # every term. These are the cases the shape has to keep getting right, because
  # a naive count of matching words gets all three wrong.
  test 'search requires every term on the same event' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: alpha only here')
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:10 host svc[1]: beta only here')
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:20 host svc[1]: alpha and beta here')
    EventIngestor.performPendingInserts

    both = Event.search('alpha beta', (Time.now - 1.year)..Time.now)
    assert_equal 1, both.count, 'an event holding one term must not match a two-term query'
    assert_includes both.first.hunks, 'alpha and beta'
  end

  # 'test' is a prefix of 'testservice', so one word satisfies both terms.
  # Counting matching *words* rather than matching *terms* would report 2 and
  # hide this event.
  test 'search counts terms, not words, when one term is a prefix of another' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: testservice reports')
    EventIngestor.performPendingInserts

    assert_equal 1, Event.search('test testservice', (Time.now - 1.year)..Time.now).count,
      'one word covering both terms must still satisfy the query'
  end

  # A term that matches no word at all must exclude every event, not silently
  # drop out of the conjunction.
  test 'search returns nothing when any term matches no word' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: alpha present here')
    EventIngestor.performPendingInserts

    assert_equal 1, Event.search('alpha', (Time.now - 1.year)..Time.now).count
    assert_equal [], Event.search('alpha nosuchwordatall', (Time.now - 1.year)..Time.now)
  end

  # Repeated words on one event must not inflate the term count.
  test 'search is not fooled by duplicate words on one event' do
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: alpha alpha beta')
    EventIngestor.performPendingInserts

    assert_equal 1, Event.search('alpha beta', (Time.now - 1.year)..Time.now).count
    assert_equal 0, Event.search('alpha beta gamma', (Time.now - 1.year)..Time.now).count
  end

  test 'storeEvent preserves single quotes instead of rewriting them' do
    EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:00 host svc[1]: don't stop believin'")
    EventIngestor.performPendingInserts
    assert_equal "1.1.1.1 Jun 1 00:00:00 host svc[1]: don't stop believin'", Event.last.hunks
  end

  test 'storeEvent stores hostile log lines verbatim without executing them' do
    before = Event.count
    line = %q{1.1.1.1 Jun 1 00:00:00 host svc[1]: '); drop table events; --}
    EventIngestor.storeEvent(line)
    EventIngestor.performPendingInserts

    assert_equal before + 1, Event.count
    assert Event.table_exists?
    assert_equal line, Event.last.hunks
  end

  test 'insertStatement binds every value and interpolates none' do
    rows = [{ :a => 1, :b => "x'y" }, { :a => 2, :b => 'z"q' }]
    sql, binds = EventIngestor.insertStatement('tablename', %i[a b], rows)
    assert_equal 'INSERT INTO tablename (a, b) VALUES (?, ?), (?, ?)', sql
    assert_equal [1, "x'y", 2, 'z"q'], binds
  end

  test 'bulk inserts across several flushes all land' do
    before = Event.count
    EventIngestor.bulk_insert_size = 5
    12.times do |i|
      EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i % 10} host svc[1]: bulk row #{i}")
    end
    EventIngestor.performPendingInserts
    assert_equal before + 12, Event.count
  ensure
    EventIngestor.bulk_insert_size = 1000
  end
end
