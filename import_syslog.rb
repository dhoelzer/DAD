#!/usr/bin/env ruby
require './config/environment.rb'
require './lib/log_queue.rb'
require './lib/log_retention.rb'

# How long a file stays in ProcessedLogs before deletion. Keep it generous: the
# files are the only record of what was ingested, and shortening this after the
# fact cannot recover anything already deleted.
RETENTION_DAYS = 7
PROCESSED_DIR = '../ProcessedLogs'
PURGE_INTERVAL = 12.hours

# One pass over every staged log file: claims each one, feeds its lines to
# Event.storeEvent, then marks it processed.
#
# Reports progress every 50 files through Rails.logger, so severity and
# timestamps survive into the Passenger log. A line that raises StandardError is
# logged and skipped; only a non-StandardError stops the pass. Ctrl-C flushes
# before exiting, so nothing already parsed is lost.
#
# The directories are parameters rather than hardcoded so the pass can be driven
# against a temporary queue in tests.
# Reads one claimed file, resuming at the offset a previous run checkpointed.
#
# The offset is what makes reclaim safe: rows committed before a crash are
# already durable, so re-reading from byte 0 would insert them a second time.
# Event only hands the writer an offset once that batch's rows are committed, so
# the checkpoint never runs ahead of the database.
#
# That ordering gives at-least-once, not exactly-once: a crash with a batch in
# flight re-reads that batch, so up to one batch's rows can be duplicated. A
# crash cannot *lose* rows that were already committed, and the duplication is
# bounded to one batch because MAX_INSERT_THREADS is 1 -- the next batch is not
# queued until the previous one has committed and released its checkpoint. A
# deliberate trade-off; see "Ingest semantics" in the README and RECOMMENDATIONS 2.2.
#
# A line that raises StandardError is logged and skipped; the pass continues.
# This used to flush and exit 1, which meant one unparseable line stopped
# ingestion for the whole deployment -- and because the checkpoint is rewound to
# that line, the restart re-read it and exited again. The pipeline was wedged
# permanently by a single bad record, with nothing restarting the process (§5.1).
#
# Skipping is safe here for a specific reason: storeEvent stages a line
# all-or-nothing, so a failed line leaves nothing behind. Its offset is simply
# never recorded, and the next staged line's offset covers it (offsets only move
# forward). The skipped line is counted, logged at warn with its text, and
# reported per pass as a Statistic so a rising failure rate is visible instead of
# silent.
#
# Anything that is not a StandardError still stops the run. Those are the errors
# that genuinely invalidate it -- NoMemoryError, SignalException, a connection
# dying -- and continuing past them would produce a partially ingested file with
# no record of what went wrong.
def process_file(in_flight, processed_dir)
  resume = LogQueue.read_offset(in_flight)
  Event.begin_ingest(resume) { |offset| LogQueue.write_offset(in_flight, offset) }

  failures = 0
  File.open(in_flight, 'r') do |file|
    file.seek(resume)
    loop do
      line_start = file.pos
      line = file.gets
      break if line.nil?

      begin
        Event.storeEvent(line, file.pos)
        yield
      rescue StandardError => e
        failures += 1
        Rails.logger.warn("Skipping unprocessable line at byte #{line_start} of #{in_flight}: #{e.class}: #{e.message}")
        Rails.logger.warn("Offending line: #{line}")
        # Keep the batch that did stage, so a bad line costs one record rather
        # than the whole file's work so far.
        Event.flush_and_wait
      rescue Exception => e
        Rails.logger.error("Fatal error processing #{in_flight} at byte #{line_start}: #{e.class}: #{e.message}")
        Rails.logger.error("Offending line: #{line}")
        # Leave the file claimed and rewind the checkpoint to the start of this
        # line: its rows were never staged, so a restart must retry it rather
        # than skip it.
        Event.flush_and_wait
        LogQueue.write_offset(in_flight, line_start)
        raise
      end
    end
  end

  # Durable before the file leaves the queue. Without this the last batch can
  # still be in flight when the file is moved to ProcessedLogs, and a crash then
  # loses rows with no .processing file left to recover them from.
  Event.flush_and_wait
  LogQueue.complete(in_flight, processed_dir)
  failures
end

# One pass over every staged log file. Returns the number of lines ingested;
# skipped lines are counted, logged, and recorded as a Statistic separately.
def process_logs(queue_dir = '.', processed_dir = PROCESSED_DIR)
  Event.resetStats # reset event timing counters
  LogQueue.reclaim(queue_dir).each { |name| Rails.logger.info("Reclaiming abandoned #{name}") }
  logs = LogQueue.pending(queue_dir)
  processed = 0
  lines = 0
  failures = 0
  begin
    logs.each do |log|
      processed += 1
      if processed % 50 == 0
        Rails.logger.info("Processing #{log}:  Log #{processed} out of #{logs.count}")
      end

      # Claim before reading. If this process dies mid-file, the remainder is
      # visible as .processing and reclaimed on the next pass instead of being
      # re-read from scratch by a queue that never knew it had been started.
      in_flight = LogQueue.claim(log)
      failures += process_file(in_flight, processed_dir) { lines += 1 }
    end
  rescue Interrupt
    Rails.logger.info("Halting operations... Emptying memory queues...")
    Event.flush_and_wait
    raise
  end
  Event.flush_and_wait
  Statistic.logLinesProcessed(lines)
  # Only written when something was actually skipped: the series is a signal that
  # lines are being lost, not a per-pass heartbeat, and a zero row per pass would
  # bury the non-zero ones on the same chart.
  Statistic.logLineFailures(failures) if failures > 0
  if failures > 0
    Rails.logger.warn("Skipped #{failures} unprocessable line(s) across #{logs.count} file(s) this pass")
  end
  lines
end

# Deletes processed logs older than RETENTION_DAYS. Reports what it actually
# removed: the previous version was an empty method whose caller still printed
# "Purged logs older than: ...", so the importer claimed a cleanup it never did
# while ProcessedLogs grew without bound on the same disk as the live queue.
def purge_logs(processed_dir = PROCESSED_DIR)
  purged = LogRetention.purge(processed_dir, max_age: RETENTION_DAYS * 24 * 60 * 60)
  Rails.logger.info("Purged #{purged} from #{processed_dir}")
  purged
end

# The loop only runs when the script is executed directly. Requiring the file --
# which the tests do -- defines the methods without chdir-ing the process or
# starting a second importer.
if __FILE__ == $PROGRAM_NAME
  # Rails' own logger writes to log/<env>.log. Run as a service, the process
  # should talk to its supervisor (the journal under systemd), and a daemon that
  # is silent in the journal looks hung. Broadcast to stdout as well so severity
  # and timestamps are kept and the operator can still see the pipeline working.
  #
  # Only here: tests require this file, and leaving Rails.logger alone lets them
  # install their own.
  Rails.logger = ActiveSupport::BroadcastLogger.new(
    Rails.logger, ActiveSupport::Logger.new($stdout))

  Dir.chdir('Logs/LogsToProcess')
  # Backdate the marker so the first pass purges, catching anything left over
  # from a previous run.
  reference_time = Time.now - (PURGE_INTERVAL + 1.hour)

  loop do
    process_logs
    if Time.now - PURGE_INTERVAL > reference_time
      reference_time = Time.now
      purge_logs
    end
    sleep 1.minute
  end
end
