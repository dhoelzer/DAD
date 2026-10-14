# Deletes files under a directory that are older than a retention window.
#
# Used by import_syslog.rb to keep ../ProcessedLogs from growing without bound on
# the same filesystem as the live queue. Replaces a commented-out
# `find . -mtime +1 | xargs rm -Rf`: shell interpolation of a path and an
# unbounded rm were both avoidable.
#
# Only regular files are removed. Symlinks are neither followed nor deleted, and
# directories are descended into but never removed, so a wrong argument cannot
# take the tree down with it.
module LogRetention
  Result = Struct.new(:deleted, :bytes) do
    def to_s
      "#{deleted} file(s), #{(bytes / 1024.0 / 1024).round(1)} MiB"
    end
  end

  ONE_DAY = 24 * 60 * 60

  # Removes files under +dir+ whose mtime is at or before now - max_age.
  # Returns a Result counting what was actually removed, so callers can report
  # real numbers instead of claiming a purge happened.
  #
  # Returns an empty Result when +dir+ does not exist: a missing ProcessedLogs
  # directory means "nothing to clean", not an error, and the importer must not
  # die over it.
  def self.purge(dir, max_age: ONE_DAY, now: Time.now)
    result = Result.new(0, 0)
    walk(dir, now - max_age, result)
    result
  end

  # Depth-first, lstat-based descent. Entries are read with Dir.entries rather
  # than Find.find so an unreadable subdirectory is reported and skipped instead
  # of raising out of the importer's main loop.
  def self.walk(dir, cutoff, result)
    return unless File.directory?(dir)

    begin
      entries = Dir.entries(dir) - %w[. ..]
    rescue SystemCallError => e
      warn "LogRetention: cannot read #{dir}: #{e.message}"
      return
    end

    entries.each do |name|
      path = File.join(dir, name)
      begin
        stat = File.lstat(path)
      rescue SystemCallError
        next
      end

      case stat.ftype
      when 'directory'
        walk(path, cutoff, result)
      when 'file'
        next if stat.mtime > cutoff
        begin
          File.delete(path)
          result.deleted += 1
          result.bytes += stat.size
        rescue SystemCallError
          # Raced with another process, or not ours to delete. The next pass
          # retries; not worth stopping ingestion for.
          next
        end
      end
      # symlinks, sockets, devices: left alone.
    end
  end
  private_class_method :walk
end
