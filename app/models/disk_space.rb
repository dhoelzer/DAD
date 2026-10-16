# Filesystem measurement for whatever partition holds a given path.
#
# Extracted because two callers need it and previously disagreed: the
# disk_utilization job grepped `df -m` for the *root* filesystem only, while
# archive pruning needs the filesystem holding offline_storage, which is
# deliberately allowed to live on a different mount.
module DiskSpace
  # [total_bytes, free_bytes] for the filesystem holding +dir+, or nil when it
  # cannot be measured.
  #
  # df -Pk is the POSIX form: it fixes the column layout and reports 1024-byte
  # blocks, so it does not shift between GNU and BSD df the way `df -m` does.
  #
  # Returns nil rather than 0 on failure. The old helper's `split(...)[4].to_i`
  # turned a missed grep into "0% used", which reads as an empty disk to an
  # operator and, if it ever fed a deletion decision, would authorise deleting
  # everything. Callers must handle nil.
  def self.measure(dir)
    return nil if dir.nil?
    out = IO.popen(['df', '-Pk', dir.to_s], err: %i[child out], &:read)
    return nil unless $?.success?
    parse_df_output(out)
  rescue StandardError => e
    Rails.logger.warn "DiskSpace: cannot measure #{dir}: #{e.message}"
    nil
  end

  # [total_bytes, available_bytes] from `df -Pk` text, or nil if it does not
  # parse. Split out so the parsing is testable against exact output rather than
  # against whatever the host's df happens to print.
  def self.parse_df_output(out)
    # Header line, then one line per filesystem; -P guarantees a single line.
    fields = out.to_s.lines.last.to_s.split
    return nil if fields.size < 4
    total = Integer(fields[1]) * 1024
    # Field 4 is *available*, not free: a slice of the filesystem is reserved
    # for root, and the app runs as the service user, so available is the number
    # that actually bounds whether a write will succeed.
    available = Integer(fields[3]) * 1024
    return nil if total <= 0
    [total, available]
  rescue ArgumentError, IndexError
    nil
  end

  # Percentage of +dir+'s filesystem in use, or nil when unmeasurable.
  #
  # Computed from total and available rather than taken from df's own Use% column
  # so that used + free sums to exactly 100, which is what the dashboard's pie
  # needs. It counts root's reserved blocks as used, which is the conservative
  # direction for a service that cannot write into them anyway.
  def self.percent_used(dir)
    total, available = measure(dir)
    return nil if total.nil? || total.zero?
    ((total - available) * 100 / total)
  end
end
