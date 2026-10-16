require 'test_helper'

# The checkpoint machinery around the threaded INSERT path.
#
# event_ingest_flush_test.rb covers the writer itself (rows land, failures
# surface, no orphans). What it does not cover is the offset bookkeeping that
# makes reclaim-after-crash safe: begin_ingest, advance_checkpoint! and
# join_insert_threads appear in no test file at all.
#
# Those are the dangerous ones, because their failure mode is silent data loss
# rather than an error. The checkpoint is the only thing telling a recovering run
# where to resume; if it runs ahead of the rows that are actually durable, the
# next run seeks past lines that were never written and they are gone with
# nothing left to notice.
#
# Subprocesses with RAILS_ENV=development, for the reason documented in
# event_ingest_flush_test.rb: Rails.env.test? selects the inline branch, and the
# inline branch cannot exercise ordering between two writer threads at all.
class EventIngestCheckpointTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby

  def setup
    @db = Tempfile.new(['ingest_ckpt', '.sqlite3'])
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
      [RUBY, '-W0', '-e', "require './config/environment'; #{body}"],
      err: %i[child out], &:read
    )
    [out, $?.exitstatus]
  end

  BOOT = "load 'db/schema.rb'; EventIngestor.resetCaches; " \
         "EventIngestor.bulk_insert_size = 1000; "

  # Records every offset the checkpoint writer is handed, as exact "label:offset"
  # tokens. begin_ingest takes the writer as a block, so the offsets are
  # observable without touching LogQueue (lib/ is not autoloaded; the model
  # deliberately never names that constant).
  #
  # Tokens rather than a joined blob: a substring assert on "file2:30" also
  # matches inside "file2:300", which turns a passing invariant into a false
  # failure. Assertions below compare whole arrays.
  RECORD = <<~'PATCH'
    $written = []
    def ck(label)
      lambda { |offset| $written << "#{label}:#{offset}" }
    end
    def dump(label)
      puts "WRITTEN[#{label}]=[#{$written.join('|')}]"
      $written.clear
    end
  PATCH

  def offsets(out, label)
    out[/WRITTEN\[#{label}\]=\[(.*)\]/, 1].to_s.split('|')
  end

  def line(i)
    format('1.1.1.1 Jun 1 00:00:%02d host svc[1]: checkpoint probe %d', i, i)
  end

  # begin_ingest drains the previous file before installing the new checkpoint
  # writer. The comment in event.rb calls this out: an unwritten batch from file
  # 1 still carries file 1's byte offsets, and if it commits after file 2's
  # writer is installed, those offsets get checkpointed into file 2's sidecar. A
  # reclaim then seeks file 2 past lines it never read.
  test 'begin_ingest drains the previous file before installing a new writer' do
    out, status = run_development(BOOT + RECORD + <<~RUBY)
      EventIngestor.begin_ingest(0, &ck('file1'))
      3.times { |i| EventIngestor.storeEvent(#{line(1).inspect}, 10 * (i + 1)) }
      # Deliberately no flush: a batch from file 1 is still in flight, holding
      # file 1's offsets, when file 2 begins.
      EventIngestor.begin_ingest(0, &ck('file2'))
      3.times { |i| EventIngestor.storeEvent(#{line(4).inspect}, 100 * (i + 1)) }
      EventIngestor.flush_and_wait
      dump('all')
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    # File 1's offsets must land on file 1's writer (the drain), and file 2's
    # only on file 2's. Anything crossing is the bug.
    assert_equal ['file1:30', 'file2:300'], offsets(out, 'all'),
      'no offset may be checkpointed into another file'"'"'s sidecar'
  end

  # advance_checkpoint! releases only batches at the head of the queue. A later
  # batch that finished first and released its own offset would tell a
  # recovering run to skip the earlier batch's lines, which were still unwritten
  # at that moment.
  #
  # Built from IngestBatch structs with fake threads rather than two real writer
  # threads: MAX_INSERT_THREADS is 1 precisely because SQLite permits a single
  # writer, so two concurrent write transactions would fail with BusyException
  # and test the database rather than the ordering rule. Raising the constant to
  # 2 is the obvious throughput change, and this is the invariant it must not
  # break.
  test 'advance_checkpoint! releases only the head of the queue' do
    out, status = run_development(BOOT + RECORD + <<~'RUBY')
      slow = EventIngestor::IngestBatch.new(Thread.new { sleep 0.4 }, 10, false)
      fast = EventIngestor::IngestBatch.new(Thread.new { :done }, 20, true)
      EventIngestor.in_flight_queue = [slow, fast]
      EventIngestor.checkpoint_writer = ck('f')

      EventIngestor.advance_checkpoint!
      dump('while head unwritten')

      slow.thread.join
      slow.finished = true
      EventIngestor.advance_checkpoint!
      dump('after head lands')
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_equal [], offsets(out, 'while head unwritten'),
      'a finished later batch must not release its offset while the head is unwritten'
    assert_equal %w[f:10 f:20], offsets(out, 'after head lands'),
      'offsets must be released in queue order once the head lands'
  end

  # A batch whose thread died must not advance the checkpoint, and the failure
  # must reach the caller. If a dead batch released its offset, the importer
  # would resume past lines that were never stored.
  test 'a failed batch neither advances the checkpoint nor is swallowed' do
    out, status = run_development(BOOT + RECORD + FAIL_ON_SECOND_INSERT + <<~RUBY)
      EventIngestor.begin_ingest(0, &ck('f'))
      2.times { |i| EventIngestor.storeEvent(#{line(1).inspect}, 10) }
      EventIngestor.flush_and_wait
      2.times { |i| EventIngestor.storeEvent(#{line(3).inspect}, 20) }
      begin
        EventIngestor.flush_and_wait
        puts 'NO_RAISE'
      rescue ActiveRecord::StatementInvalid
        puts 'RAISED'
      end
      dump('after failure')
      puts "ROWS=#{Event.count}"
    RUBY

    assert_equal 0, status, "subprocess failed:\n#{out}"
    assert_includes out, 'RAISED'
    refute_includes out, 'NO_RAISE'
    assert_equal ['f:10'], offsets(out, 'after failure'),
      'the committed batch must be checkpointed; the failed one must not'
    assert_includes out, 'ROWS=2'
  end

  FAIL_ON_SECOND_INSERT = <<~'PATCH'
    class ActiveRecord::ConnectionAdapters::SQLite3Adapter
      alias_method :orig_exec_query, :exec_query
      def exec_query(sql, *args, **kwargs)
        if sql.include?('INSERT INTO events (')
          $ev ||= 0
          $ev += 1
          raise ActiveRecord::StatementInvalid, 'forced failure' if $ev > 1
        end
        orig_exec_query(sql, *args, **kwargs)
      end
    end;
  PATCH
end
