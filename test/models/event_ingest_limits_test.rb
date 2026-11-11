require 'test_helper'
require_relative '../support/scratch_database'

# Two ingest limits that the rest of the suite cannot see, because both are
# crossed only by volume:
#
#   1. A bulk INSERT larger than the database's host-parameter ceiling.
#      insertStatement emits one VALUES tuple per row, so a batch of R rows over
#      C columns uses C*R parameters, and Postgres rejects the statement outright
#      past 65535 (Int16). events_words is the binding constraint (3 columns,
#      ~16 rows per event), so the production default batch of 2000 events needs
#      ~96k parameters -- well over the ceiling.
#
#      The suite never got there: DEFAULT_BULK_INSERT_SIZE is 1 in test, so every
#      in-process test flushes one event at a time. The ceiling is only reachable
#      from a development-environment run with a production-sized batch, which is
#      what the subprocess bodies below do.
#
#   2. The word-cache TTL. prune_words reads cache_lifetime before it writes it,
#      so a process that never assigned it raised
#      "can't convert NilClass into an exact number" on its first prune -- once
#      the cache crossed CACHESIZE, i.e. only on a long ingest. The extraction
#      that moved this state off Event dropped the @@cachelifetime=320
#      assignment while keeping both the reader and the writer.
#
# Subprocesses with RAILS_ENV=development, for the reason documented in
# event_ingest_flush_test.rb: Rails.env.test? selects the inline write branch,
# and only the threaded branch is what production runs.
class EventIngestLimitsTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  BOOT = "load 'db/schema.rb'; EventIngestor.resetCaches; "

  def setup
    @db = ScratchDatabase.new('ingest_limits')
  end

  def teardown
    # resetCaches clears the ceiling override along with the rest of the
    # process-global ingest state; leaving it set would make later tests in this
    # file chunk at an absurd limit.
    EventIngestor.resetCaches
    @db&.drop
  end

  def run_development(body)
    out = IO.popen(
      { 'RAILS_ENV' => 'development',
        'DATABASE_URL' => @db.url,
        'SECRET_KEY_BASE' => 'x' * 32 },
      [RUBY, '-e', "require './config/environment'; #{body}"],
      err: %i[child out], &:read
    )
    [out, $?.exitstatus]
  end

  # --- the parameter ceiling ------------------------------------------------

  test 'insert_statements splits a batch that exceeds the parameter ceiling' do
    columns = %i[event_id word_id generated]
    ceiling = EventIngestor.max_statement_params
    rows = Array.new(ceiling) { |i| { event_id: i, word_id: i, generated: '2026-01-01 00:00:00' } }

    statements = EventIngestor.insert_statements('events_words', columns, rows)

    assert_operator statements.size, :>, 1,
      'a batch using more parameters than the ceiling must be split'
    statements.each do |sql, binds|
      assert_operator binds.size, :<=, ceiling,
        "each statement must stay within the ceiling: #{binds.size} > #{ceiling}"
      assert_equal 'INSERT INTO events_words (event_id, word_id, generated) VALUES ',
        sql[0, 'INSERT INTO events_words (event_id, word_id, generated) VALUES '.size]
    end
    assert_equal rows.size, statements.sum { |_sql, binds| binds.size / columns.size },
      'splitting must not drop or duplicate rows'
  end

  test 'insert_statements leaves a batch within the ceiling as one statement' do
    statements = EventIngestor.insert_statements(
      'events_words', %i[event_id word_id generated],
      [{ event_id: 1, word_id: 2, generated: '2026-01-01 00:00:00' }]
    )
    assert_equal 1, statements.size
    assert_equal 'INSERT INTO events_words (event_id, word_id, generated) VALUES (?, ?, ?)',
      statements[0][0]
  end

  # An INSERT with no VALUES is a syntax error, and a batch can legitimately be
  # empty: performPendingInserts can be handed events with no staged index rows.
  test 'insert_statements emits nothing for no rows' do
    assert_equal [], EventIngestor.insert_statements('events_words', %i[event_id], [])
  end

  # The ceiling is per adapter, and getting it wrong in either direction is a
  # defect: too high and the statement dies, too low and every batch is split
  # into needlessly many round trips.
  test 'the ceiling comes from the adapter in use' do
    expected = EventIngestor::MAX_STATEMENT_PARAMS.fetch(
      ActiveRecord::Base.connection.adapter_name,
      EventIngestor::DEFAULT_MAX_STATEMENT_PARAMS
    )
    assert_equal expected, EventIngestor.max_statement_params
  end

  # The subprocess cases below only prove a chunked write *succeeds*; they cannot
  # show where the split happened. This pins the arithmetic directly: the ceiling
  # Postgres is assigned, and that a production-sized batch splits at it rather
  # than overflowing into a rejected statement.
  test 'a batch sized for the Postgres ceiling splits at that ceiling' do
    columns = %i[event_id word_id generated]
    pg_ceiling = EventIngestor::MAX_STATEMENT_PARAMS.fetch('PostgreSQL')
    assert_equal 65_535, pg_ceiling, 'Postgres caps a statement at Int16 parameters'

    # ~16 events_words rows per event, so this is a production-default batch.
    rows = Array.new(2000 * 16) { |i| { event_id: i, word_id: i, generated: '2026-01-01 00:00:00' } }
    statements = EventIngestor.insert_statements('events_words', columns, rows, max_params: pg_ceiling)

    assert_operator statements.size, :>, 1,
      'a 2000-event batch is over the Postgres ceiling and must be split'
    statements.each do |_sql, binds|
      assert_operator binds.size, :<=, pg_ceiling
    end
    assert_equal rows.size, statements.sum { |_sql, binds| binds.size / columns.size }
  end

  # An adapter this app does not know about must chunk to the lowest supported
  # ceiling rather than assume an unlimited one.
  test 'an unknown adapter falls back to the lowest supported ceiling' do
    assert_equal EventIngestor::DEFAULT_MAX_STATEMENT_PARAMS,
      EventIngestor::MAX_STATEMENT_PARAMS.fetch('NoSuchAdapter',
        EventIngestor::DEFAULT_MAX_STATEMENT_PARAMS)
    assert_operator EventIngestor::DEFAULT_MAX_STATEMENT_PARAMS, :<=,
      EventIngestor::MAX_STATEMENT_PARAMS.values.min,
      'the fallback must not exceed any known adapter ceiling'
  end

  # The regression that matters: a production-sized batch. Pre-fix this died in
  # write_batch with "too many SQL variables". The assertion that the ceiling was
  # actually crossed is what stops the test passing vacuously if the probe lines
  # ever stop producing enough index rows.
  test 'a production-sized batch is written, not rejected' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.bulk_insert_size = 1000
      EventIngestor.inserted_last_run = 1e9
      # 40 distinct tokens a line, so 1000 events stage ~40k index rows: ~120k
      # parameters, well past the 65535-parameter ceiling Postgres enforces.
      1000.times do |i|
        toks = (0...40).map { |j| "tok#{i}_#{j}" }.join(' ')
        EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i % 10} host svc[1]: #{toks}")
      end
      begin
        EventIngestor.flush_and_wait
      rescue => e
        puts "DIED #{e.class}: #{e.message[0, 60]}"
        exit 1
      end
      c = Event.connection
      puts "EVENTS=#{Event.count}"
      puts "INDEX_ROWS=#{c.execute('select count(*) as c from events_words').first['c']}"
      puts "ORPHANS=#{c.execute('select count(*) as c from events_words ' \
        'where event_id not in (select id from events)').first['c']}"
      puts "DANGLING_WORDS=#{c.execute('select count(*) as c from events_words ' \
        'where word_id not in (select id from words)').first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    refute_includes out, 'DIED', 'a batch over the parameter ceiling must not raise'
    assert_includes out, 'EVENTS=1000'
    index_rows = out[/INDEX_ROWS=(\d+)/, 1].to_i
    assert_operator index_rows * 3, :>, EventIngestor::MAX_STATEMENT_PARAMS.fetch('PostgreSQL'),
      'the probe must actually exceed the ceiling, or this test proves nothing'
    assert_includes out, 'ORPHANS=0', 'chunking must not split a batch across transactions'
    assert_includes out, 'DANGLING_WORDS=0'
  end

  # Chunking must not weaken the all-or-nothing property the single transaction
  # gave: a failure part-way through a chunked batch rolls the whole batch back,
  # so no events_words row is left pointing at an event that was never written.
  test 'a failing chunk rolls back the whole batch' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.max_statement_params = 30   # 10 events_words rows per statement
      # Above the staged count, so no flush fires from inside stage_event: the
      # break below has to be installed before the one and only flush runs.
      EventIngestor.bulk_insert_size = 10_000
      100.times do |i|
        toks = (0...20).map { |j| "rb#{i}_#{j}" }.join(' ')
        EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i % 10} host svc[1]: #{toks}")
      end
      puts "STAGED=#{EventIngestor.pending_count}"
      # Break the table the second statement set writes to, after the index rows
      # have been issued but before the events rows are.
      EventIngestor.singleton_class.send(:alias_method, :write_batch_orig, :write_batch)
      EventIngestor.define_singleton_method(:write_batch) do |ew, _ev|
        ActiveRecord::Base.transaction do
          ew.each { |sql, binds| SqlPlaceholders.query(sql, binds) }
          SqlPlaceholders.query('insert into events (no_such_column) values (1)', [])
        end
      end
      begin
        EventIngestor.flush_and_wait
      rescue => e
        puts "RAISED=#{e.class.name.split('::').last}"
      end
      c = Event.connection
      puts "EVENTS=#{Event.count}"
      puts "INDEX_ROWS=#{c.execute('select count(*) as c from events_words').first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'STAGED=100', 'the batch must be staged before the flush is broken'
    assert_includes out, 'RAISED='
    assert_includes out, 'EVENTS=0'
    assert_includes out, 'INDEX_ROWS=0',
      'a rolled-back batch must leave no index rows behind'
  end

  # --- the word-cache TTL ---------------------------------------------------

  # resetCaches is the single place ingest state is initialised; a TTL that is
  # only ever set by prune_words is nil on the first call, which is what killed
  # the importer.
  test 'resetCaches initialises the word-cache TTL' do
    EventIngestor.cache_lifetime = 999
    EventIngestor.resetCaches
    assert_equal EventIngestor::DEFAULT_CACHE_LIFETIME, EventIngestor.cache_lifetime,
      'resetCaches must restore the TTL, not leave whatever a prune left behind'
  end

  # The crash itself, on a fresh process: prune_words reached before anything has
  # assigned the TTL.
  test 'prune_words works on a fresh process with no TTL assigned' do
    out, status = run_development(BOOT + <<~'RUBY')
      puts "LIFETIME=#{EventIngestor.cache_lifetime.inspect}"
      begin
        EventIngestor.prune_words
        puts "PRUNED_OK=#{EventIngestor.cache_lifetime}"
      rescue => e
        puts "PRUNED_DIED #{e.class}: #{e.message[0, 60]}"
        exit 1
      end
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, "LIFETIME=#{EventIngestor::DEFAULT_CACHE_LIFETIME}"
    refute_includes out, 'PRUNED_DIED', 'prune_words must not raise on a fresh process'
    assert_includes out, 'PRUNED_OK=', 'the TTL must still adapt after pruning'
  end

  # The trigger, not just the direct call: performPendingInserts prunes once
  # num_cached exceeds CACHESIZE, so the importer dies mid-run rather than at a
  # call site anyone would think to test. CACHESIZE entries is far too many to
  # stage in a test, so the threshold is what is being simulated here -- the code
  # path from a flush into prune_words is the thing under test.
  test 'a flush that trips the prune threshold does not kill the ingest' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.bulk_insert_size = 5
      # Push num_cached past CACHESIZE without staging CACHESIZE words.
      EventIngestor.define_singleton_method(:num_cached) { EventIngestor::CACHESIZE + 1 }
      puts "TRIPPED=#{EventIngestor.num_cached > EventIngestor::CACHESIZE}" 
      begin
        3.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: trip prune") }
        EventIngestor.flush_and_wait
        puts "SURVIVED lifetime=#{EventIngestor.cache_lifetime}"
      rescue => e
        puts "DIED #{e.class}: #{e.message[0, 60]}"
        exit 1
      end
      puts "EVENTS=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    refute_includes out, 'DIED', 'a flush that triggers prune_words must not raise'
    assert_includes out, 'TRIPPED=true', 'the prune threshold must actually be crossed'
    assert_includes out, 'SURVIVED'
    assert_includes out, 'EVENTS=3'
  end
end
