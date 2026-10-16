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

  def self.quote(name)
    EventPartitioning.quote(name)
  end
end
