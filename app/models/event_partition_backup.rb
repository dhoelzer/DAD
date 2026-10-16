# Backs up event partitions to disk before retention drops them.
#
# Retention is DROP TABLE on a month's partition (see EventPartitioning): fast,
# but destructive, and until now there was no way to recover a dropped month.
# This writes each expiring partition to a CSV file under an offline_storage
# directory first, and the drop is skipped for any partition whose archive did
# not complete, so retention can never destroy the only copy of a month's rows.
#
# Ordering is the whole design: archive, verify the file, then drop. An archive
# that fails leaves the partition in place for the next run to retry, which is
# what makes the scheduled job safe to re-run forever.
#
# Why COPY and not pg_dump: pg_dump --table <partition> emits
# `ALTER TABLE events ATTACH PARTITION ...` and a DEFAULT nextval reference to
# the parent's sequence, so the output only loads into a database that already
# has the parent and its sequence. Verified against Postgres 17: restoring such a
# dump into a fresh database recovers zero rows. Client-side COPY produces plain
# CSV that loads anywhere, needs no superuser (server-side COPY would write as
# the postgres OS user), and removes the subprocess, the pg_dump binary and its
# version coupling from the recovery path entirely.
#
# Postgres-only, like the retention it guards.
#
# Restoring: see bin/restore_event_partition, which recreates the partition and
# loads the CSV back. The files are plain CSV with a header row, so they are
# also directly readable without any restore step.
require 'csv'

module EventPartitionBackup
  # Default directory name, resolved under Rails.root unless
  # DAD_OFFLINE_STORAGE_DIR gives an absolute path.
  DEFAULT_DIRNAME = 'offline_storage'.freeze

  ARCHIVE_SUFFIX = '.csv'.freeze

  # Writes +partition_name+ to <dir>/<partition_name>.csv and returns its path,
  # or nil when the archive did not complete.
  #
  # Writes to <name>.csv.part and renames only on success, so a run killed
  # part-way cannot leave a truncated file that a later run mistakes for a
  # completed archive and drops the partition over.
  def self.backup_partition(table, partition_name, dir: storage_dir)
    final_path = File.join(dir, "#{partition_name}#{ARCHIVE_SUFFIX}")
    return final_path if archived?(partition_name, dir: dir)

    tmp_path = "#{final_path}.part"
    rows = nil
    begin
      FileUtils.mkdir_p(dir)
      # Savepoint, not just a rescue: a COPY that fails aborts the whole Postgres
      # transaction, so without this one bad partition would take the rest of the
      # maintain run down with it instead of being skipped.
      ActiveRecord::Base.connection.transaction(requires_new: true) do
        rows = copy_partition_to_file(partition_name, tmp_path)
      end
    rescue StandardError => e
      # Deliberately broad: every failure mode here (missing partition, adapter
      # without COPY, disk full, permissions) must end the same way -- no
      # archive, and therefore no drop. Narrowing this list risks an unhandled
      # error escaping into the scheduler instead of the partition surviving.
      Rails.logger.warn "EventPartitionBackup: archiving #{partition_name} failed: #{e.message}"
      rows = nil
    end

    if rows.nil? || rows.negative? || !File.file?(tmp_path) || File.size(tmp_path).zero?
      File.delete(tmp_path) if File.file?(tmp_path)
      return nil
    end
    File.rename(tmp_path, final_path)
    final_path
  end

  # True when a completed archive exists for +partition_name+.
  def self.archived?(partition_name, dir: storage_dir)
    path = archive_path(partition_name, dir: dir)
    File.file?(path) && File.size(path).positive?
  end

  def self.archive_path(partition_name, dir: storage_dir)
    File.join(dir, "#{partition_name}#{ARCHIVE_SUFFIX}")
  end

  # Streams one partition to +path+ as CSV with a header row, returning the
  # number of data rows written.
  #
  # Client-side COPY (TO STDOUT): the file is written by the Rails process, so
  # it lands wherever the app is allowed to write and needs no
  # pg_write_server_files. The partition name is validated by #quote before it
  # reaches the SQL.
  #
  # copy_data lives on the raw PG::Connection, not the Rails adapter. In pg 1.x
  # the block's first yield is the COPY-out Result, not data, so the lines have
  # to be pulled with get_copy_data; treating that Result as a line wrote an
  # object's #inspect into the archive.
  def self.copy_partition_to_file(partition_name, path)
    raw = ActiveRecord::Base.connection.raw_connection
    rows = 0
    File.open(path, 'w') do |file|
      raw.copy_data("COPY (SELECT * FROM #{quote(partition_name)}) " \
                    'TO STDOUT WITH (FORMAT csv, HEADER true)') do
        while (line = raw.get_copy_data)
          file.write(line)
          rows += 1
        end
      end
    end
    # HEADER true writes the column names as the first line, so subtract it.
    rows - 1
  end

  # Loads +path+ into +table+, returning the number of data rows sent.
  #
  # FROM STDIN with an explicit column list taken from the file's header: the
  # archive was written by SELECT *, so its column order is the table's, but
  # naming the columns keeps a restore correct if the table has since gained any.
  # HEADER true makes Postgres skip the header line itself.
  def self.restore_partition(path, table)
    raise ArgumentError, "no archive at #{path}" unless File.file?(path)
    raw = ActiveRecord::Base.connection.raw_connection
    header = File.open(path, &:readline).chomp
    columns = CSV.parse_line(header).map { |name| quote(name) }.join(', ')
    sent = 0
    raw.copy_data("COPY #{quote(table)} (#{columns}) FROM STDIN WITH (FORMAT csv, HEADER true)") do
      File.foreach(path) do |line|
        raw.put_copy_data(line)
        sent += 1
      end
    end
    sent - 1
  end

  # Where archives live. DAD_OFFLINE_STORAGE_DIR overrides; a relative value is
  # taken from Rails.root so a systemd unit with a different WorkingDirectory
  # still lands in the same place. Empty counts as unset: a systemd EnvironmentFile
  # line written as `KEY=` yields an empty string, not a missing key.
  def self.storage_dir
    configured = ENV.fetch('DAD_OFFLINE_STORAGE_DIR', '').strip
    configured = DEFAULT_DIRNAME if configured.empty?
    Pathname.new(configured).absolute? ? configured : Rails.root.join(configured).to_s
  end

  # --- archive retention ------------------------------------------------------
  #
  # Archives are the last copy of a dropped month, so pruning them destroys
  # history. It is therefore off unless an operator sets a free-space floor on
  # the archive partition (Preference.archiveFreeSpacePercent, Admin-gated).
  #
  # The failure this prevents: nothing used to reclaim the archive directory, so
  # on a long-lived install it grows until the disk fills, archiving starts
  # failing, and -- because a drop is gated on a completed archive -- partitions
  # stop being dropped. The database then grows instead of the disk filling,
  # which is the worse of the two outcomes.

  # Free-space floor as a percentage (0-100), or nil when pruning is disabled.
  def self.free_space_percent
    percent = Preference.archiveFreeSpacePercent
    return nil if percent.nil? || percent.to_i <= 0
    percent.to_i
  end

  # [total_bytes, available_bytes] for the filesystem holding +dir+, or nil when
  # it cannot be measured. Delegates to DiskSpace so the dashboard and the
  # pruner measure the same way.
  def self.disk_space(dir)
    DiskSpace.measure(dir)
  end
  # Archives on disk, oldest month first, as [path, bytes, month].
  #
  # Ordered by the month carried in the partition name, not by mtime: an archive
  # restored or copied by hand gets a fresh mtime, and pruning by mtime would
  # then delete the oldest history while keeping a recently-copied one.
  #
  # Files that do not parse as one of our archives are left out entirely, so a
  # stray file in the directory is never deleted by this code.
  def self.archives(dir = storage_dir)
    Dir.glob(File.join(dir, "*#{ARCHIVE_SUFFIX}")).filter_map do |path|
      name = File.basename(path, ARCHIVE_SUFFIX)
      _table, prefix = EventPartitioning::PARTITION_PREFIXES.find { |_t, pfx| name.start_with?(pfx) }
      next if prefix.nil?
      month = EventPartitioning.partition_month(name, prefix)
      next if month.nil?
      [path, File.size(path), month]
    end.sort_by { |path, _bytes, month| [month, path] }
  end

  # Bytes the next archive is expected to need, estimated from the largest of the
  # most recent archives. Months are broadly comparable in size, and taking the
  # largest of several errs towards pruning too early rather than too late.
  #
  # Only a fallback: #upcoming_archive_bytes measures the real thing when the
  # partitions are still in the database.
  def self.estimated_archive_bytes(dir = storage_dir)
    archives(dir).last(3).map { |_path, bytes, _month| bytes }.max || 0
  end

  # Total bytes the named partitions occupy, as a stand-in for the size of the
  # archives about to be written from them.
  #
  # pg_relation_size, not pg_total_relation_size: the CSV holds table rows only,
  # so indexes are not part of the archive, and counting them would over-estimate
  # the need and delete more history than the disk actually requires. Under-
  # estimating is the safe direction here -- an archive that runs out of room
  # fails, leaves its partition in place, and is retried next run, whereas an
  # over-estimate destroys months nobody needed to lose.
  #
  # Returns nil when the sizes cannot be read, so the caller falls back to the
  # on-disk estimate rather than treating an error as "zero bytes needed".
  def self.partition_sizes(names)
    return 0 if names.empty?
    # One placeholder per name: the pg adapter cannot bind a Ruby Array to
    # ANY($1), so the IN list is built positionally rather than as a literal.
    placeholders = names.each_with_index.map { |_n, i| "$#{i + 1}" }.join(', ')
    row = EventPartitioning.execute(
      'SELECT COALESCE(SUM(pg_relation_size(c.oid)), 0) AS bytes FROM pg_class c ' \
      "WHERE c.relname IN (#{placeholders})", names
    ).first
    row['bytes'].to_i
  rescue StandardError => e
    Rails.logger.warn "EventPartitionBackup: could not size #{names.join(', ')}: #{e.message}"
    nil
  end

  # Bytes the archives for +partition_names+ are expected to need: measured from
  # the partitions where possible, estimated from existing archives otherwise.
  #
  # Partitions that already have a complete archive are excluded: backup_partition
  # returns the existing file without re-writing it, so those cost nothing to
  # "write" and charging them would prune history that was never needed.
  def self.upcoming_archive_bytes(partition_names, dir = storage_dir)
    pending = Array(partition_names).reject { |name| archived?(name, dir: dir) }
    return 0 if pending.empty?
    measured = partition_sizes(pending)
    return measured if measured && measured.positive?
    estimated_archive_bytes(dir) * pending.size
  end

  # Deletes whole months, oldest first, until the partition keeps the required
  # free space once +needed_bytes+ more has been written.
  #
  # Returns a hash: :deleted (paths), :bytes (freed), :free_bytes /
  # :required_free_bytes (the measurement it worked to), :short (bytes still
  # short after everything prunable was deleted), :error (why nothing was done).
  #
  # Fails closed. If the filesystem cannot be measured, nothing is deleted: a
  # bogus reading would delete history for no reason, and the cost of not
  # pruning is a disk warning, while the cost of pruning on a bad reading is
  # lost months.
  #
  # +disk+ is injectable so the arithmetic can be tested against exact numbers
  # rather than against whatever the test machine's filesystem happens to hold.
  #
  # +protected+ names partitions whose archives must be left alone. The caller
  # passes the partitions it is about to archive: deleting one of those frees
  # bytes that the very next step spends again re-writing it, so counting them
  # as freed makes the deficit arithmetic optimistic and the floor can come out
  # breached after a run that reported a successful prune.
  def self.prune_archives(dir: storage_dir, percent: free_space_percent,
                          needed_bytes: 0, dry_run: false, disk: disk_space(dir),
                          protected: [])
    return { deleted: [], bytes: 0, short: 0, error: 'pruning disabled: no free-space floor set' } if percent.nil?
    return { deleted: [], bytes: 0, short: 0 } unless File.directory?(dir)

    total, free = disk
    if total.nil?
      msg = "cannot measure the filesystem holding #{dir}; not pruning any archives"
      Rails.logger.warn "EventPartitionBackup: #{msg}"
      return { deleted: [], bytes: 0, short: 0, error: msg }
    end

    required_free = total * percent / 100
    deficit = required_free - free + needed_bytes.to_i
    return { deleted: [], bytes: 0, short: 0, free_bytes: free, required_free_bytes: required_free } if deficit <= 0

    protected = Array(protected).map(&:to_s)
    list = archives(dir).reject do |path, _bytes, _month|
      protected.include?(File.basename(path, ARCHIVE_SUFFIX))
    end
    deleted = []
    freed = 0
    list.each do |path, bytes, _month|
      break if freed >= deficit
      deleted << path
      freed += bytes
    end

    unless dry_run
      deleted.each do |path|
        begin
          File.delete(path)
        rescue StandardError => e
          Rails.logger.warn "EventPartitionBackup: could not delete archive #{path}: #{e.message}"
        end
      end
    end

    {
      deleted: deleted, bytes: freed, free_bytes: free, required_free_bytes: required_free,
      short: deficit - freed, dry_run: dry_run
    }
  end

  def self.quote(name)
    EventPartitioning.quote(name)
  end
end
