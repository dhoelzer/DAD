require 'fileutils'

# The on-disk queue the syslog importer works through.
#
# Files live in LogsToProcess. A file is claimed by renaming it to
# <name>.processing *before* its lines are read, and moved to ProcessedLogs only
# once every line has been consumed. That ordering is the point: a process that
# dies part-way through leaves a .processing file behind, which the next run can
# see and reclaim, instead of a queue that never knew the file had been started.
#
# A .processing file also has a .processing.offset sidecar recording how far the
# dead process got. Re-reading from the top would re-insert rows the dead process
# already committed, so the offset is what makes reclaim safe. See read_offset.
module LogQueue
  IN_FLIGHT_SUFFIX = '.processing'
  # Sidecar holding the byte offset to resume from, named after the in-flight
  # file: <name>.processing.offset
  OFFSET_SUFFIX = '.offset'

  # Files waiting to be read, excluding anything already claimed.
  #
  # The File.file? filter matters: Dir.glob("*") also returns directories, and
  # the importer reads each result with File.foreach, which raises
  # IsADirectoryError on one.
  #
  # Offset sidecars are excluded too: X.processing.offset does not end in
  # .processing, so without this filter it would be treated as an unread log.
  def self.pending(dir)
    return [] unless File.directory?(dir)

    Dir.glob(File.join(dir, '*')).sort.select do |path|
      File.file?(path) && !claimed?(path) && !offset_path?(path)
    end
  end

  # Files a previous run claimed but never finished.
  def self.abandoned(dir)
    return [] unless File.directory?(dir)

    Dir.glob(File.join(dir, "*#{IN_FLIGHT_SUFFIX}")).reject { |p| offset_path?(p) }
  end

  # Puts abandoned files back in the queue and returns the original names.
  #
  # The offset sidecar travels with the file so the next claim resumes where the
  # dead run stopped rather than re-inserting rows it already committed.
  def self.reclaim(dir)
    abandoned(dir).map do |path|
      original = path.sub(/#{Regexp.escape(IN_FLIGHT_SUFFIX)}\z/, '')
      File.rename(path, original)
      sidecar = offset_path(path)
      File.rename(sidecar, offset_path(original)) if File.exist?(sidecar)
      File.basename(original)
    end
  end

  # Claims a file for this process, returning the in-flight path to read from.
  def self.claim(path)
    in_flight = "#{path}#{IN_FLIGHT_SUFFIX}"
    File.rename(path, in_flight)
    sidecar = "#{path}#{OFFSET_SUFFIX}"
    File.rename(sidecar, offset_path(in_flight)) if File.exist?(sidecar)
    in_flight
  end

  # Marks a claimed file as fully consumed by moving it to +dest_dir+ under its
  # original name, i.e. with the in-flight suffix stripped. The sidecar is
  # discarded: there is nothing left to resume.
  def self.complete(in_flight_path, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    original = File.basename(in_flight_path).sub(/#{Regexp.escape(IN_FLIGHT_SUFFIX)}\z/, '')
    File.rename(in_flight_path, File.join(dest_dir, original))
    Dir.glob("#{offset_path(in_flight_path)}*").each { |f| File.unlink(f) }
  end

  def self.offset_path(in_flight_path)
    "#{in_flight_path}#{OFFSET_SUFFIX}"
  end

  # True for a checkpoint sidecar or its temp file, at any depth of naming.
  #
  # include? rather than end_with? because write_offset renames
  # <name>.offset.tmp into <name>.offset, and a process killed between the two
  # leaves the .tmp behind. That name ends in .processing once it has been
  # through claim's rename, so an end_with? filter here would let a sidecar be
  # treated as a log file and read as syslog input.
  def self.offset_path?(path)
    File.basename(path).include?(OFFSET_SUFFIX)
  end

  def self.claimed?(path)
    File.basename(path).end_with?(IN_FLIGHT_SUFFIX)
  end

  # Bytes already known-durable for an in-flight file. 0 when there is no
  # sidecar, i.e. the file has never been started or nothing was committed.
  def self.read_offset(in_flight_path)
    File.read(offset_path(in_flight_path)).to_i
  rescue Errno::ENOENT
    0
  end

  # Records +offset+ as durable for +in_flight_path+.
  #
  # Only ever called once the rows for those bytes are committed, so a crash
  # after this point costs at most the batch that was just written.
  #
  # Written as temp-then-rename: a crash mid-write would otherwise leave a
  # truncated offset, and a short offset silently skips lines.
  #
  # A no-op when the in-flight file is gone -- the run finished and moved it, so
  # a late checkpoint from a joined thread must not resurrect a sidecar.
  def self.write_offset(in_flight_path, offset)
    return unless File.exist?(in_flight_path)

    sidecar = offset_path(in_flight_path)
    tmp = "#{sidecar}.tmp"
    File.binwrite(tmp, offset.to_s)
    File.rename(tmp, sidecar)
  end
end
