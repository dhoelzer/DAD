require 'test_helper'

# Two pieces of the threaded ingest path that the other subprocess suites leave
# uncovered: the back-pressure branch in performPendingInserts, and prune_words.
#
# event_ingest_flush_test.rb covers the writer (rows land, failures surface, no
# orphans) and event_ingest_checkpoint_test.rb covers the offset bookkeeping.
# Neither drives repeated flushes while a writer is still in flight, which is the
# importer's normal shape: storeEvent calls performPendingInserts itself, and the
# importer never calls flush_and_wait between batches. That is the only route
# through the `@@insertThreads.count >= MAX_INSERT_THREADS` branch.
#
# prune_words had no coverage on this path at all: it is referenced only from job
# tests, which never populate the word cache. Its failure modes are silent -- a
# cache that keeps stale ids writes events_words rows pointing at words that no
# longer exist, and a cache whose counter is not reset re-prunes on every flush
# forever.
#
# Subprocesses with RAILS_ENV=development, for the reason documented in
# event_ingest_flush_test.rb: Rails.env.test? selects the inline branch, and the
# inline branch never starts a writer thread.
#
# Every body below uses a non-interpolating heredoc. An interpolating one silently
# evaluates #{Event.count} in *this* process against the fixture database, which
# reports a number the subprocess never produced.
class EventIngestBackpressureTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  BOOT = "load 'db/schema.rb'; EventIngestor.resetCaches; " \
         "EventIngestor.bulk_insert_size = 1000; "

  # Counts concurrent write_batch calls and how often the drain ran. The
  # concurrency counter is the point: MAX_INSERT_THREADS is the ceiling on
  # in-flight writers, and the only way to check a ceiling is to observe overlap
  # rather than infer it from the queue length, which advance_checkpoint! drains
  # as batches finish.
  #
  # The sleep makes the writer slow enough that the next flush reliably finds a
  # batch still in flight; without it the batches finish before the next flush and
  # the branch under test never runs.
  INSTRUMENT = <<~'PATCH'
    $active = 0; $max_concurrent = 0; $joins = 0
    $mu = Mutex.new
    EventIngestor.singleton_class.send(:alias_method, :join_orig, :join_insert_threads)
    EventIngestor.define_singleton_method(:join_insert_threads) do
      $joins += 1
      EventIngestor.send(:join_orig)
    end
    EventIngestor.singleton_class.send(:alias_method, :write_batch_orig, :write_batch)
    EventIngestor.define_singleton_method(:write_batch) do |*args|
      $mu.synchronize { $active += 1; $max_concurrent = [$max_concurrent, $active].max }
      begin
        sleep 0.25
        EventIngestor.send(:write_batch_orig, *args)
      ensure
        $mu.synchronize { $active -= 1 }
      end
    end;
  PATCH

  def setup
    @db = Tempfile.new(['ingest_backpressure', '.sqlite3'])
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

  # The importer's real shape: repeated flushes, no explicit drain in between.
  # Each flush finds the previous batch still writing and takes the join branch.
  # Without that branch the queue grows one thread per flush, and every thread
  # holds a connection from a pool of 5.
  test 'repeated flushes never exceed MAX_INSERT_THREADS concurrent writers' do
    out, status = run_development(BOOT + INSTRUMENT + <<~'RUBY')
      5.times do |round|
        2.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{round} host svc[1]: backpressure probe #{round}", 10 * (i + 1)) }
        EventIngestor.performPendingInserts
      end
      EventIngestor.flush_and_wait
      puts "MAX_CONCURRENT=#{$max_concurrent}"
      puts "JOINS=#{$joins}"
      puts "EVENTS=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, "MAX_CONCURRENT=#{EventIngestor::MAX_INSERT_THREADS}",
      'in-flight writers must be capped by MAX_INSERT_THREADS'
    assert_operator out[/JOINS=(\d+)/, 1].to_i, :>=, 2,
      'the back-pressure branch must actually be exercised'
    assert_includes out, 'EVENTS=10', 'back-pressure must not drop staged rows'
  end

  # Same shape, asserting the database survives it. A drain that raced the writer
  # would leave events_words rows whose event never got written.
  test 'back-pressure leaves a consistent events/events_words pair' do
    out, status = run_development(BOOT + INSTRUMENT + <<~'RUBY')
      EventIngestor.begin_ingest(0) { |_off| nil }
      4.times do |round|
        3.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:1#{round} host svc[1]: drain probe #{round}-#{i}", 10 * (i + 1)) }
        EventIngestor.performPendingInserts
      end
      EventIngestor.flush_and_wait
      puts "EVENTS=#{Event.count}"
      puts "ORPHANS=#{Event.connection.execute('select count(*) as c from events_words ' \
        'where event_id not in (select id from events)').first['c']}"
      puts "DANGLING_WORDS=#{Event.connection.execute('select count(*) as c from events_words ' \
        'where word_id not in (select id from words)').first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'EVENTS=12'
    assert_includes out, 'ORPHANS=0'
    assert_includes out, 'DANGLING_WORDS=0'
  end

  # prune_words drops entries whose :last is older than the TTL and keeps the
  # rest. Get the comparison backwards and the importer either re-queries every
  # word on every line or holds ids forever.
  test 'prune_words drops stale entries and keeps recently used ones' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.cache_lifetime = 3600
      2.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: prune fresh #{i}", 10) }
      EventIngestor.flush_and_wait

      cache = EventIngestor.cached_words
      # Age exactly one entry out; the rest stay inside the TTL.
      stale_key = cache.keys.first
      cache[stale_key][:last] = Time.now - 7200
      before = cache.keys.count

      EventIngestor.prune_words
      after = EventIngestor.cached_words

      puts "BEFORE=#{before}"
      puts "AFTER=#{after.keys.count}"
      puts "STALE_GONE=#{!after.key?(stale_key)}"
      puts "FRESH_KEPT=#{(after.keys - [stale_key]).count == before - 1}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    before = out[/BEFORE=(\d+)/, 1].to_i
    after = out[/AFTER=(\d+)/, 1].to_i
    assert_operator before, :>, 0, 'the probe must have populated the word cache'
    assert_includes out, 'STALE_GONE=true'
    assert_includes out, 'FRESH_KEPT=true'
    assert_equal before - 1, after, 'exactly the stale entry should be dropped'
  end

  # The counter is what gates the call: performPendingInserts prunes only once
  # @@num_cached exceeds CACHESIZE. If pruning left the counter alone, every later
  # flush would re-prune an already-small cache, forever.
  test 'prune_words resets the counter that gates it' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.cache_lifetime = 3600
      3.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: counter probe #{i}", 10) }
      EventIngestor.flush_and_wait

      EventIngestor.cached_words.each_value { |v| v[:last] = Time.now - 7200 }
      EventIngestor.prune_words

      puts "CACHE=#{EventIngestor.cached_words.keys.count}"
      puts "NUM_CACHED=#{EventIngestor.num_cached}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'CACHE=0'
    assert_includes out, 'NUM_CACHED=0',
      'the counter that triggers pruning must track the pruned cache size'
  end

  # The correctness risk of a live cache: after a prune the words have to be
  # re-derived from the database. A pruned entry that left an id behind would
  # index events against word ids that do not exist, and searching for those words
  # would silently return nothing.
  test 'words re-resolve to valid ids after a prune' do
    out, status = run_development(BOOT + <<~'RUBY')
      EventIngestor.cache_lifetime = 3600
      2.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:0#{i} host svc[1]: revalidate tokenz #{i}", 10) }
      EventIngestor.flush_and_wait

      EventIngestor.cached_words.each_value { |v| v[:last] = Time.now - 7200 }
      EventIngestor.prune_words

      2.times { |i| EventIngestor.storeEvent("1.1.1.1 Jun 1 00:00:1#{i} host svc[1]: revalidate tokenz #{i}", 20) }
      EventIngestor.flush_and_wait

      puts "EVENTS=#{Event.count}"
      puts "DANGLING_WORDS=#{Event.connection.execute('select count(*) as c from events_words ' \
        'where word_id not in (select id from words)').first['c']}"
      puts "TOKENZ_HITS=#{Event.connection.execute("select count(*) as c from events_words " \
        "where word_id = (select id from words where text = 'tokenz')").first['c']}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'EVENTS=4', 'both pre- and post-prune batches must be stored'
    assert_includes out, 'DANGLING_WORDS=0',
      'a pruned word must not leave an index row pointing at a missing word id'
    assert_includes out, 'TOKENZ_HITS=4',
      'the word must be re-added and indexed for every event that mentions it'
  end
end
