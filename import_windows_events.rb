#!/usr/bin/env ruby
# Tails an OpenWEC output file and enqueues converted Windows events.
#
# This is the process an operator runs; lib/windows_forward.rb holds the parts
# and is loaded by tests. The loop here is deliberately thin: read from the last
# offset, convert, flush a complete file into the queue, sleep.
#
# It does not import. dad-importer already polls LogsToProcess and owns the
# checkpointing, batching and word indexing; a second importer would race it for
# the same files. One queue, one importer.
#
# The input is whatever OpenWEC's Files output driver writes. Point a
# subscription at it, e.g. in openwec.conf.toml:
#
#   [[subscription]]
#   name = "Security"
#   [subscription.output.files]
#   path = "/var/DAD/Logs/Windows"
#   file_name = "openwec.log"
#   format = "Json"          # Json | Nxlog | Raw | JsonRaw all work
#
# Where that output goes matters: OpenWEC must write somewhere the syslog
# collector is not using. Logs/LogStaging belongs to the Rust collector, whose
# recover_orphans() moves every file it finds there into LogsToProcess at
# startup, on the stated assumption that it is the only writer. A converter
# appending there would have its in-progress file renamed away mid-write.
require './config/environment.rb'
require './lib/windows_forward'

# Paths are read per pass rather than frozen into constants at load, so the loop
# body can be driven against a scratch tree in tests, and so pointing the daemon
# at a new location is one line in the unit file rather than an edit here.

# OpenWEC's output file. Read from the beginning on first run, then resumed.
def input_path
  ENV.fetch('WINDOWS_INPUT', 'Logs/Windows/openwec.log')
end

# Where converted lines are buffered before being published. Must differ from
# the queue directory: LogQueue.pending globs '*' and would otherwise claim a
# half-written file and read it while it is still being appended to.
def staging_dir
  ENV.fetch('WINDOWS_STAGING', 'Logs/WindowsStaging')
end

# The queue dad-importer polls.
def queue_dir
  ENV.fetch('WINDOWS_QUEUE', 'Logs/LogsToProcess')
end

# Lines per queue file. Bounds how much is in flight if this process dies, and
# how large a single importer pass gets.
def max_lines
  Integer(ENV.fetch('WINDOWS_MAX_LINES', 5000))
end

def poll_interval
  Integer(ENV.fetch('WINDOWS_POLL_INTERVAL', 10))
end

def offset_path
  "#{input_path}.dad-offset"
end

# One pass: tail whatever arrived since the last pass, convert it, and publish.
# Returns the number of lines enqueued.
def convert_pass(writer)
  reader = WindowsForward::Reader.new(input_path)
  enqueued = 0
  skipped = 0

  offset = WindowsForward::Offset.read(offset_path)
  new_offset = reader.each_record(offset) do |record|
    line = WindowsEvents.convert(record)
    if line.nil?
      skipped += 1
    else
      writer << line
      enqueued += 1
    end
  end

  # Offset after flush, never before. If the offset moved first and this process
  # then died, the next pass would start past lines that were never enqueued and
  # those events would be gone. Writing it after the rename makes the pipeline
  # at-least-once instead: a crash in between re-sends a file that was already
  # published, the same trade-off the importer makes per batch.
  published = writer.flush
  WindowsForward::Offset.write(offset_path, new_offset) if new_offset != offset

  Rails.logger.warn("windows_forward: skipped #{skipped} unconvertible record(s)") if skipped > 0
  Rails.logger.info("windows_forward: enqueued #{enqueued} line(s) as #{published}") if published
  enqueued
end

if __FILE__ == $PROGRAM_NAME
  # Same reason as import_syslog.rb: a daemon that is silent in the journal looks
  # hung. Only here, so tests keep their own logger.
  Rails.logger = ActiveSupport::BroadcastLogger.new(
    Rails.logger, ActiveSupport::Logger.new($stdout))

  unless File.exist?(input_path)
    Rails.logger.warn(
      "windows_forward: no input at #{input_path}. Set WINDOWS_INPUT to the file " \
      "OpenWEC's Files output driver writes. Waiting for it to appear.")
  end

  writer = WindowsForward::Writer.new(staging_dir, queue_dir, max_lines: max_lines)

  loop do
    begin
      convert_pass(writer) if File.exist?(input_path)
    rescue StandardError => e
      # One bad record must not stop ingestion for the whole deployment -- the
      # same lesson import_syslog.rb learned the hard way. Anything that is not a
      # StandardError still propagates and lets the supervisor restart us.
      Rails.logger.error("windows_forward: pass failed: #{e.class}: #{e.message}")
    end
    sleep poll_interval
  end
end
