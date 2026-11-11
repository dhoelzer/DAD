# Tails an OpenWEC output file and writes DAD staging lines into the ingest queue.
#
# OpenWEC's Files driver appends exactly one '\n' per record, and its Json,
# Nxlog and JsonRaw formats are produced by serde_json::to_string, which emits
# no newlines -- so those are one record per line. The Raw format is the
# exception: it hands back the untouched Windows XML, and a rendered event
# message (RenderingInfo/Message) contains literal newlines. One Raw record
# therefore spans many lines in the output file. Reader#each_record frames those
# records back apart; without it, a single 4688 with a rendered message becomes
# a dozen garbage lines.
#
# The queue discipline here deliberately mirrors LogQueue rather than inventing
# a second one: a file is written under a .inprogress name and only renamed into
# LogsToProcess once it is complete, so the importer never reads a partial file.
#
# One thing this must not do: write into Logs/LogStaging. That directory belongs
# to the Rust syslog collector, whose recover_orphans() moves *every* file it
# finds there into LogsToProcess at startup on the stated assumption that "this
# is the only writer". A converter writing there would have its in-progress file
# renamed out from under it mid-append. Hence a separate staging directory.
require 'fileutils'
require_relative 'windows_events'

module WindowsForward
  # A record is buffered until it parses, then flushed. This bounds what a
  # never-completing Raw record (truncated by a crash mid-write) can hold in
  # memory before it is dropped and logged.
  MAX_RECORD_BYTES = 1_000_000

  # Reads complete records from an OpenWEC output file, resuming at a byte
  # offset. Yields each record's text with no trailing newline.
  class Reader
    def initialize(path)
      @path = path
    end

    # Yields records, then returns the byte offset to resume from.
    #
    # The offset only advances past records that were yielded, so a record still
    # being written when the file ends is re-read on the next pass rather than
    # lost. That makes the pipeline at-least-once, matching the importer.
    def each_record(resume_offset = 0)
      return 0 unless File.exist?(@path)

      offset = resume_offset
      buffer = +''
      File.open(@path, 'r') do |file|
        file.seek(offset)
        while (line = file.gets)
          if buffer.empty? && !starts_record?(line)
            # Continuation of something we never started, or trailing junk
            # between records. Skipping keeps one bad byte from wedging the tail.
            offset = file.pos
            next
          end
          buffer << line
          if record_complete?(buffer)
            yield buffer.chomp
            buffer = +''
            offset = file.pos
          elsif buffer.bytesize > MAX_RECORD_BYTES
            warn "windows_forward: dropping unterminated record (#{buffer.bytesize} bytes) at offset #{offset}"
            buffer = +''
            offset = file.pos
          end
        end
      end
      offset
    end

    private

    def starts_record?(line)
      first = line.lstrip[0]
      first == '{' || first == '<'
    end

    # A JSON record is always one line. An XML record is complete once the
    # accumulated text parses with an <Event> root; Nokogiri is lenient, so the
    # closing tag is checked explicitly rather than trusting a successful parse.
    def record_complete?(buffer)
      text = buffer.strip
      return false if text.empty?
      return text.end_with?('}') if text[0] == '{'
      text.end_with?('</Event>')
    end
  end

  # Buffers converted lines and hands them to the queue as complete files.
  #
  # Files land in +staging_dir+ under a .inprogress name and are renamed into
  # +queue_dir+ on flush, which is what makes them invisible to the importer
  # until they are finished.
  class Writer
    attr_reader :flushes

    def initialize(staging_dir, queue_dir, prefix: 'windows', max_lines: 5000)
      @staging_dir = staging_dir
      @queue_dir = queue_dir
      @prefix = prefix
      @max_lines = max_lines
      @lines = []
      @flushes = 0
      # LogQueue.pending globs '*' in the queue directory and excludes only
      # *.processing and *.offset sidecars, so a half-written file sitting in the
      # queue directory would be claimed and read while still being appended to.
      # The .inprogress name only buys anything because it lives elsewhere.
      raise ArgumentError, "staging_dir and queue_dir must differ" if
        File.expand_path(@staging_dir) == File.expand_path(@queue_dir)
      FileUtils.mkdir_p(@staging_dir)
      FileUtils.mkdir_p(@queue_dir)
    end

    def <<(line)
      @lines << line
      flush if @lines.size >= @max_lines
    end

    def pending?
      !@lines.empty?
    end

    # Writes the buffer as one queue file and returns its final name, or nil
    # when there was nothing to write.
    #
    # The rename is atomic within a filesystem, which is the whole point: the
    # importer's LogQueue.pending only ever sees a fully written file.
    def flush
      return nil if @lines.empty?

      name = "#{@prefix}.#{Time.now.to_i}.#{$PROCESS_ID}.#{@flushes}"
      in_progress = File.join(@staging_dir, "#{name}.inprogress")
      File.open(in_progress, 'w') do |f|
        @lines.each { |l| f.puts(l) }
        f.flush
        f.fsync
      end
      File.rename(in_progress, File.join(@queue_dir, name))
      @flushes += 1
      @lines = []
      name
    end
  end

  # Tracks how far the tail has read, so a restart resumes instead of
  # re-ingesting the whole file. Same shape as LogQueue's offset sidecar.
  module Offset
    def self.read(path)
      return 0 unless File.exist?(path)
      File.read(path).to_i
    rescue StandardError
      0
    end

    def self.write(path, offset)
      tmp = "#{path}.tmp"
      File.open(tmp, 'w') { |f| f.write(offset.to_s) }
      File.rename(tmp, path)
    end
  end
end
