require 'test_helper'

# Exercises the threaded INSERT path that performPendingInserts takes in every
# non-test environment. Before this file that code had no coverage at all --
# grep insertThreads test/ returned nothing.
#
# It runs in a subprocess with RAILS_ENV=development because the in-process suite
# cannot: Rails.env.test? selects the inline branch, and that branch exists for a
# real reason -- the suite and Cucumber hold an open transaction, and SQLite
# permits a single writer, so a second one deadlocks them.
#
# Each case therefore drains the queue (flush_and_wait) before staging more work.
# That keeps exactly one writer active at a time, which is what makes these
# assertions deterministic on SQLite rather than a race against
# SQLite3::BusyException. The thread itself is still what does the writing, which
# is the behaviour under test.
class EventIngestFlushTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  # Builds the schema in a throwaway database, clears Event's class-level caches,
  # and raises the batch size.
  #
  # The batch size matters: it is 1 in development, so storeEvent flushes after
  # every single line. Left at 1 these cases race -- a failed batch surfaced at
  # whichever call happened to notice the dead thread, not the one being asserted
  # on. A high value means only the explicit flushes below stage work.
  BOOT = "load 'db/schema.rb'; EventIngestor.resetCaches; " \
         "EventIngestor.bulk_insert_size = 1000; "

  # Replaces the adapter's exec_query so the events INSERT fails on demand.
  # Patched on the adapter, not ActiveRecord::Base: exec_query is a connection
  # method, and aliasing a method that does not exist raises NameError.
  #
  # The signature is splat/kwargs rather than the adapter's own (sql, name, binds,
  # prepare:) so the patch keeps working across Rails versions: 4.2 passes three
  # positionals, 5.2 adds a prepare: keyword, and later versions add more.
  FAIL_ON_EVENTS_INSERT = <<~'PATCH'
    class ActiveRecord::ConnectionAdapters::SQLite3Adapter
      alias_method :orig_exec_query, :exec_query
      def exec_query(sql, *args, **kwargs)
        raise ActiveRecord::StatementInvalid, 'forced failure' if sql.include?('INSERT INTO events (')
        orig_exec_query(sql, *args, **kwargs)
      end
    end;
  PATCH

  ORPHANS_SQL = "select count(*) as c from events_words " \
                "where event_id not in (select id from events)"

  def setup
    @db = Tempfile.new(['ingest_flush', '.sqlite3'])
    @db.close
  end

  def teardown
    @db.unlink rescue nil
  end

  def run_development(body)
    out = IO.popen(
      { 'RAILS_ENV' => 'development',
        'DATABASE_URL' => "sqlite3:#{@db.path}",
        'SECRET_KEY_BASE' => 'x' * 32 },
      [RUBY, '-e', "require './config/environment'; #{body}"],
      err: %i[child out], &:read
    )
    [out, $?.exitstatus]
  end

  # The batch is observed by whether write_batch ran off the main thread, not by
  # counting @@insertThreads: a writer that finishes fast now releases its batch
  # from the queue itself, so the count is 0 or 1 depending on timing.
  RECORD_THREAD = <<~'PATCH'
    EventIngestor.singleton_class.send(:alias_method, :write_batch_orig, :write_batch)
    EventIngestor.define_singleton_method(:write_batch) do |*args|
      $off_main = true if Thread.current != Thread.main
      # send: write_batch is private_class_method.
      EventIngestor.send(:write_batch_orig, *args)
    end;
  PATCH

  test 'the threaded path writes events and their index rows' do
    out, status = run_development(BOOT + RECORD_THREAD + <<~'RUBY')
      3.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: threaded probe #{i}") }
      EventIngestor.performPendingInserts
      EventIngestor.flush_and_wait
      puts "OFF_MAIN=#{$off_main}"
      puts "EVENTS=#{Event.count}"
      puts "INDEX_ROWS=#{Event.connection.execute('select count(*) as c from events_words').first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'OFF_MAIN=true', 'the threaded branch must have been taken'
    assert_includes out, 'EVENTS=3'
    assert_operator out[/INDEX_ROWS=(\d+)/, 1].to_i, :>, 0, 'events_words rows must be written too'
  end

  test 'a failed threaded batch is surfaced, not swallowed' do
    out, status = run_development(BOOT + FAIL_ON_EVENTS_INSERT + <<~'RUBY')
      EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 host svc[1]: doomed batch here')
      EventIngestor.performPendingInserts
      begin
        EventIngestor.flush_and_wait
        puts 'NO_RAISE'
      rescue ActiveRecord::StatementInvalid => e
        puts "RAISED=#{e.message}"
      end
      puts "EVENTS=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'RAISED=forced failure',
      'a batch that died on a background thread must reach the caller'
    assert_includes out, 'EVENTS=0'
    refute_includes out, 'NO_RAISE'
  end

  test 'a failed batch leaves no orphan index rows' do
    out, status = run_development(BOOT + FAIL_ON_EVENTS_INSERT + <<~'RUBY')
      EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:01 host svc[1]: doomed batch here')
      EventIngestor.performPendingInserts
      begin
        EventIngestor.flush_and_wait
      rescue ActiveRecord::StatementInvalid
      end
      puts "ORPHANS=#{Event.connection.execute('select count(*) as c from events_words ' \
        'where event_id not in (select id from events)').first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'ORPHANS=0',
      'events_words is inserted before events, so without a shared transaction a ' \
      'failed batch leaves index rows pointing at events that do not exist'
  end

  test 'a successful batch leaves no orphan index rows either' do
    out, status = run_development(BOOT + <<~'RUBY')
      5.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: clean batch #{i}") }
      EventIngestor.flush_and_wait
      puts "ORPHANS=#{Event.connection.execute('select count(*) as c from events_words ' \
        'where event_id not in (select id from events)').first['c']}"
      puts "EVENTS=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'EVENTS=5'
    assert_includes out, 'ORPHANS=0'
  end

  test 'a multi-row batch writes every staged event' do
    out, status = run_development(BOOT + <<~'RUBY')
      6.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i % 10} host svc[1]: batch probe #{i}") }
      EventIngestor.performPendingInserts
      EventIngestor.flush_and_wait
      puts "WRITTEN=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'WRITTEN=6', 'no row may be dropped by the join/drain logic'
  end

  # Static invariant, checked in-process: insert threads plus the main thread must
  # fit inside the pool of 5, or a flush blocks on the pool timeout instead of
  # writing. The old limit of 5 let 5 inserts plus the main thread ask for 6.
  test 'the in-flight limit leaves headroom in the connection pool' do
    # Rails 6.1 replaced the configurations hash with DatabaseConfigurations;
    # configurations['test']['pool'] now returns nil (the deprecated [] hands back
    # a symbol-keyed hash). configs_for is the API that survives into 7.x.
    # Rails 8.1 renamed the accessor pool -> max_connections and deprecated the
    # old name (removed in 8.2); database.yml's `pool:` key still feeds it.
    pool = ActiveRecord::Base.configurations.configs_for(env_name: 'test').first.max_connections
    assert_operator EventIngestor::MAX_INSERT_THREADS + 1, :<, pool,
      'insert threads plus the main thread must fit inside the pool'
  end
end
