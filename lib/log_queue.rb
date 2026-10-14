require 'fileutils'

# The on-disk queue the syslog importer works through.
#
# Files live in LogsToProcess. A file is claimed by renaming it to
# <name>.processing *before* its lines are read, and moved to ProcessedLogs only
# once every line has been consumed. That ordering is the point: a process that
# dies part-way through leaves a .processing file behind, which the next run can
# see and reclaim, instead of a queue that never knew the file had been started.
module LogQueue
  IN_FLIGHT_SUFFIX = '.processing'

  # Files waiting to be read, excluding anything already claimed.
  #
  # The File.file? filter matters: Dir.glob("*") also returns directories, and
  # the importer reads each result with File.foreach, which raises
  # IsADirectoryError on one.
  def self.pending(dir)
    return [] unless File.directory?(dir)

    Dir.glob(File.join(dir, '*')).sort.select do |path|
      File.file?(path) && !File.basename(path).end_with?(IN_FLIGHT_SUFFIX)
    end
  end

  # Files a previous run claimed but never finished.
  def self.abandoned(dir)
    return [] unless File.directory?(dir)

    Dir.glob(File.join(dir, "*#{IN_FLIGHT_SUFFIX}"))
  end

  # Puts abandoned files back in the queue and returns the original names.
  #
  # Their lines were never fully written -- whatever was still in the in-memory
  # batch died with the process -- so re-reading from the top is the correct
  # recovery. Event ids are re-seeded from MAX(id) on each run, so the re-run
  # cannot collide with rows the dead process did commit.
  def self.reclaim(dir)
    abandoned(dir).map do |path|
      original = path.sub(/#{Regexp.escape(IN_FLIGHT_SUFFIX)}\z/, '')
      File.rename(path, original)
      File.basename(original)
    end
  end

  # Claims a file for this process, returning the in-flight path to read from.
  def self.claim(path)
    in_flight = "#{path}#{IN_FLIGHT_SUFFIX}"
    File.rename(path, in_flight)
    in_flight
  end

  # Marks a claimed file as fully consumed by moving it to +dest_dir+ under its
  # original name, i.e. with the in-flight suffix stripped.
  def self.complete(in_flight_path, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    original = File.basename(in_flight_path).sub(/#{Regexp.escape(IN_FLIGHT_SUFFIX)}\z/, '')
    File.rename(in_flight_path, File.join(dest_dir, original))
  end
end
