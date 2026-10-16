# Monthly range partitioning of the event tables, and the retention that goes
# with it.
#
# Postgres-only: dev and test run SQLite, which has no partitioning. Every entry
# point here checks #supported? or is only reached from a Postgres-specific
# migration, so a SQLite install is unaffected.
#
# Why partitioning (RECOMMENDATIONS.md 3.2): events and events_words grew without
# bound, and index size, search latency and backup time all degrade with them.
# Partitioning by +generated+ turns retention into DROP TABLE on a month's
# partition -- metadata-only, so it costs the same whether the month holds 10k
# rows or 100M -- where DELETE would rewrite every index and leave the space
# unusable until a full VACUUM.
#
# It also speeds the queries the app already runs. Search always constrains
# +generated+ to a time window, so the planner prunes every partition outside it
# and scans only the months in range.
#
# Partition names carry the month (events_p202610), which is what makes retention
# possible without parsing catalog internals: the month comes from the name.
# Event.approximate_count already sums pg_stat_user_tables rows matching
# 'events_p%', so it counts the partitions and not the (empty) parent.
module EventPartitioning
  # Partitioned table => prefix its partitions carry.
  #
  # The events_words prefix deliberately does NOT match 'events_p%', so
  # approximate_count keeps counting only event rows.
  PARTITION_PREFIXES = { 'events' => 'events_p', 'events_words' => 'events_words_p' }.freeze

  # Suffix of the catch-all partition for each table.
  DEFAULT_SUFFIX = 'default'.freeze

  # Partitions created past the current month.
  #
  # Ahead of now matters because ingestion writes rows whose +generated+ is the
  # timestamp inside the log line, which can be slightly in the future (skewed
  # senders). The real safety net is the DEFAULT partition: without it a row
  # outside every range raises and takes the whole INSERT batch down with it.
  MONTHS_AHEAD = 2

  # Rows older than this are dropped, by dropping their partition.
  #
  # Read from the environment so an operator sets it per deployment alongside
  # DAD_DB_PASSWORD. The default is 365 days: a fresh install starts dropping
  # month-old partitions after about a year of history. Set it to 0 (or any
  # value <= 0) to keep every partition indefinitely.
  #
  # Dropping is gated on a completed archive under offline_storage (see
  # EventPartitionBackup), so the default does not silently destroy history:
  # a month is only dropped once its dump exists on disk.
  #
  # This is a floor, not an exact age: a partition is only dropped once its whole
  # month is older than the cutoff, so rows can survive up to a month longer.
  def self.retention_days
    value = ENV.fetch('DAD_EVENT_RETENTION_DAYS', '').strip
    value = '365' if value.empty?
    Integer(value)
  rescue ArgumentError
    raise ArgumentError, "DAD_EVENT_RETENTION_DAYS must be an integer number of days, got #{value.inspect}"
  end

  def self.supported?
    ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
  end

  # The month a partition covers, or nil for the DEFAULT partition and for any
  # partition this code did not name.
  def self.partition_month(name, prefix)
    match = name.to_s.match(/\A#{Regexp.escape(prefix)}(\d{6})\z/)
    return nil unless match
    Date.strptime(match[1], '%Y%m')
  end

  def self.partition_name(prefix, month)
    "#{prefix}#{month.strftime('%Y%m')}"
  end

  def self.default_partition_name(prefix)
    "#{prefix}#{DEFAULT_SUFFIX}"
  end

  # The scheduled entry point (JobHandler 'maintain_event_partitions').
  #
  # Creates the partitions the current month needs, archives the expired ones to
  # offline_storage, then drops the archived ones, and returns a one-line
  # summary for the scheduler log.
  #
  # Idempotent, as every handler must be: the scheduler re-runs a failing Job
  # forever, so a second pass has to be a no-op rather than an error. An
  # already-archived partition is not dumped twice, and a partition whose
  # archive failed is skipped rather than dropped.
  #
  # On SQLite it reports that there is nothing to do instead of raising, so a
  # Job row that exists in a dev database does not raise an Alert every cycle.
  def self.maintain(today: Date.today)
    unless supported?
      return 'event partitioning is Postgres-only; nothing to do'
    end

    created = ensure_partitions(today: today)
    expired = expired_partitions(today: today)
    dropped = drop_expired_partitions(today: today)
    kept = expired.size - dropped.size
    stray = default_partition_rows
    stray_note = stray.values.sum.positive? ? ", #{stray.inspect} in DEFAULT" : ''
    kept_note = kept.positive? ? ", #{kept} expired partition(s) kept pending archive" : ''
    "partitions: +#{created.size} -#{dropped.size}" \
      " (retention #{retention_days}d#{kept_note}#{stray_note})"
  end

  # Partitions that should exist: every month from the retention cutoff through
  # MONTHS_AHEAD past the current month.
  #
  # Going back to the cutoff rather than only forward means a late import of
  # in-window data lands in a real partition instead of the DEFAULT one.
  def self.expected_months(today = Date.today, keep_days: retention_days)
    current = today.beginning_of_month
    first = keep_days > 0 ? (current - ((keep_days / 30) + 1).months) : current
    months = []
    month = first
    while month <= current + MONTHS_AHEAD.months
      months << month
      month += 1.month
    end
    months
  end

  # Names every partition of +table+, keyed by name, with the month parsed from
  # the name (nil for the DEFAULT partition).
  def self.partitions(table, prefixes = PARTITION_PREFIXES)
    prefix = prefixes.fetch(table)
    sql = "select c.relname::text as name " \
          "from pg_inherits i join pg_class c on c.oid = i.inhrelid " \
          "join pg_class p on p.oid = i.inhparent " \
          "where p.relname = $1 order by c.relname"
    ActiveRecord::Base.connection.exec_query(sql, 'SQL', [table]).map do |row|
      [row['name'], partition_month(row['name'], prefixes.fetch(table))]
    end
  end

  # Creates any missing monthly partitions, plus the catch-all DEFAULT partition
  # each table needs. Returns the names created.
  #
  # The DEFAULT partition is what keeps a single out-of-range +generated+ from
  # taking down an entire INSERT batch: without it Postgres raises
  # CheckViolation ("no partition of relation ... found for row"), and the batch
  # is one statement, so every event in it is lost with the bad line.
  def self.ensure_partitions(tables: PARTITION_PREFIXES.keys, today: Date.today,
                               keep_days: retention_days, prefixes: PARTITION_PREFIXES)
    raise ArgumentError, 'partitioning requires PostgreSQL' unless supported?

    created = []
    tables.each do |table|
      prefix = prefixes.fetch(table)
      existing = partitions(table, prefixes).map(&:first)
      expected_months(today, keep_days: keep_days).each do |month|
        name = partition_name(prefix, month)
        next if existing.include?(name)
        execute_partition(table, prefix, month)
        created << name
      end
      default_name = default_partition_name(prefix)
      next if existing.include?(default_name)
      execute("CREATE TABLE #{quote(default_name)} PARTITION OF #{quote(table)} DEFAULT")
      created << default_name
    end
    created
  end

  # Creates the monthly partitions covering +first_month+ .. +last_month+
  # (inclusive), plus the DEFAULT partition. Returns the names created.
  #
  # Used by the conversion migration, which has to create partitions for whatever
  # +generated+ values already exist -- those can be far older than the retention
  # window, and copying a row with no matching partition raises CheckViolation.
  def self.ensure_partitions_covering(table, first_month, last_month, prefix: PARTITION_PREFIXES.fetch(table))
    raise ArgumentError, 'partitioning requires PostgreSQL' unless supported?

    existing = partitions(table, { table => prefix }).map(&:first)
    created = []
    return created if first_month.nil? || last_month.nil?

    month = first_month.beginning_of_month
    while month <= last_month.beginning_of_month
      name = partition_name(prefix, month)
      unless existing.include?(name)
        execute_partition(table, prefix, month)
        created << name
      end
      month += 1.month
    end
    default_name = default_partition_name(prefix)
    unless existing.include?(default_name)
      execute("CREATE TABLE #{quote(default_name)} PARTITION OF #{quote(table)} DEFAULT")
      created << default_name
    end
    created
  end

  # The month-boundary a partition must predate to be expired. Shared by
  # #drop_expired_partitions and #expired_partitions so the two cannot drift:
  # if they did, the "kept pending archive" count in #maintain would be wrong.
  def self.retention_cutoff(today = Date.today, keep_days: retention_days)
    (today - keep_days).beginning_of_month
  end

  # Drops monthly partitions whose entire month is older than the retention
  # cutoff. Returns the names dropped.
  #
  # The DEFAULT partition is never dropped: it has no month, and dropping it
  # would delete rows this code cannot account for. Its size is reported by
  # #default_partition_rows so an operator can see whether data is landing there.
  #
  # A drop is gated on a completed archive in offline_storage (see
  # EventPartitionBackup): retention must not destroy the only copy of a month.
  # When archiving fails, the partition is left in place and reported as skipped,
  # and the next run retries it. Pass archive: false to drop without archiving.
  def self.drop_expired_partitions(tables: PARTITION_PREFIXES.keys, today: Date.today,
                                    keep_days: retention_days, prefixes: PARTITION_PREFIXES,
                                    archive: true, dir: EventPartitionBackup.storage_dir)
    raise ArgumentError, 'partitioning requires PostgreSQL' unless supported?
    return [] unless keep_days > 0

    cutoff = retention_cutoff(today, keep_days: keep_days)
    dropped = []
    tables.each do |table|
      prefix = prefixes.fetch(table)
      partitions(table, prefixes).each do |name, month|
        next if month.nil? || month >= cutoff
        if archive && EventPartitionBackup.backup_partition(table, name, dir: dir).nil?
          Rails.logger.warn "EventPartitioning: keeping #{name}: archive to #{dir} failed; " \
                            'refusing to drop an unarchived partition'
          next
        end
        execute "DROP TABLE #{quote(name)}"
        dropped << name
      end
    end
    dropped
  end

  # Names the expired partitions without touching anything, so an operator (or a
  # test) can see what the next maintain run would archive and drop.
  def self.expired_partitions(tables: PARTITION_PREFIXES.keys, today: Date.today,
                               keep_days: retention_days, prefixes: PARTITION_PREFIXES)
    return [] unless keep_days > 0
    cutoff = retention_cutoff(today, keep_days: keep_days)
    tables.flat_map do |table|
      partitions(table, prefixes).filter_map do |name, month|
        name unless month.nil? || month >= cutoff
      end
    end
  end

  # Rows sitting in the DEFAULT partitions. Non-zero means ingestion met a
  # +generated+ value outside every monthly range -- usually a log line with an
  # absurd timestamp, or a month the maintenance job has not created yet.
  def self.default_partition_rows(tables: PARTITION_PREFIXES.keys, prefixes: PARTITION_PREFIXES)
    tables.to_h do |table|
      name = default_partition_name(prefixes.fetch(table))
      [table, execute("select count(*) as c from #{quote(name)}").first['c'].to_i]
    end
  end

  # True when +table+ is itself a partitioned parent.
  def self.partitioned?(table)
    row = execute("select pt.relkind as kind from pg_class pt where pt.relname = $1", [table]).first
    row && row['kind'] == 'p'
  end

  def self.execute_partition(table, prefix, month)
    name = partition_name(prefix, month)
    lower = month.strftime('%Y-%m-%d %H:%M:%S')
    upper = (month + 1.month).strftime('%Y-%m-%d %H:%M:%S')
    execute("CREATE TABLE #{quote(name)} PARTITION OF #{quote(table)} " \
            "FOR VALUES FROM ('#{lower}') TO ('#{upper}')")
  end

  def self.execute(sql, binds = [])
    ActiveRecord::Base.connection.exec_query(sql, 'SQL', binds)
  end

  # --- converting an existing unpartitioned table -------------------------------
  #
  # Postgres has no in-place conversion (ALTER TABLE ... PARTITION BY is only
  # valid in CREATE TABLE), so this builds a partitioned twin, copies, and swaps
  # the names. It lives here rather than in the migration so the data-preserving
  # path can be tested directly against scratch tables.
  #
  # The swap takes an exclusive lock and copies every row, so on a large install
  # it is a maintenance-window operation.
  #
  # Returns the names of the partitions created to receive the existing rows.
  def self.convert_to_partitioned(table, primary_key: nil, prefix: PARTITION_PREFIXES.fetch(table))
    raise ArgumentError, 'partitioning requires PostgreSQL' unless supported?
    return [] if partitioned?(table)

    old_table = "#{table}_unpartitioned"
    new_table = "#{table}_partitioned"
    columns = connection.columns(table).map(&:name)
    # Read the index definitions before renaming anything: after the rename they
    # carry the _unpartitioned prefix, and the twin must get the original names.
    indexes = connection.indexes(table)

    rename_indexes(table, indexes, old_table)
    create_partitioned_twin(new_table, table, indexes, primary_key)
    created = partitions_for_existing_rows(table, new_table, prefix)
    copy_rows(table, new_table, columns)
    repoint_sequence(table, new_table)

    connection.execute("ALTER TABLE #{connection.quote_table_name(table)} RENAME TO #{connection.quote_table_name(old_table)}")
    connection.execute("ALTER TABLE #{connection.quote_table_name(new_table)} RENAME TO #{connection.quote_table_name(table)}")
    # A PRIMARY KEY names its index after the table at creation time, so the
    # twin's carries the twin's name; put the conventional one back.
    if primary_key
      rename_index("#{new_table}_pkey", "#{table}_pkey")
    end
    connection.execute("DROP TABLE #{connection.quote_table_name(old_table)}")
    created
  end

  # Index names are unique per schema, so the twin cannot take the original's
  # names until they are free.
  #
  # The primary key's index is included too: Rails' #indexes does not report it,
  # so it has to be found through pg_constraint. Leaving it out made creating the
  # twin's PRIMARY KEY fail with "relation events_pkey already exists".
  def self.rename_indexes(table, indexes, old_table)
    indexes.each { |index| rename_index(index.name, "#{old_table}_#{index.name}") }
    pkey = connection.select_value(
      "SELECT conname FROM pg_constraint " \
      "WHERE conrelid = #{ActiveRecord::Base.connection.quote(table)}::regclass AND contype = 'p'"
    )
    rename_index(pkey, "#{old_table}_pkey") if pkey
  end

  def self.rename_index(from, to)
    execute("ALTER INDEX #{quote(from)} RENAME TO #{quote(to)}")
  end

  # Rebuilds the table as a partitioned parent, keeping every column definition
  # verbatim so the copy cannot drift from the original.
  def self.create_partitioned_twin(new_table, source_table, indexes, primary_key)
    definitions = connection.columns(source_table).map { |column| column_definition(column) }
    key = primary_key ? ", PRIMARY KEY (#{Array(primary_key).join(', ')})" : ''
    execute("CREATE TABLE #{quote(new_table)} (#{definitions.join(', ')}#{key}) " \
            'PARTITION BY RANGE (generated)')

    # Indexes on the parent propagate to every partition, including ones created
    # later, so this is the only place they need declaring.
    indexes.each do |index|
      ActiveRecord::Base.connection.add_index(new_table, index.columns,
        unique: index.unique, name: index.name)
    end
  end

  # "name type [DEFAULT x] [NOT NULL]" for one column.
  #
  # A function default (events.id's nextval) arrives in default_function with a
  # nil default, so the two must be handled separately: emitting the nil as a
  # literal produced "DEFAULT  NOT NULL" and aborted the migration.
  def self.column_definition(column)
    fragment = "#{ActiveRecord::Base.connection.quote_column_name(column.name)} #{column.sql_type}"
    if column.default_function.present?
      fragment += " DEFAULT #{column.default_function}"
    elsif column.has_default?
      fragment += " DEFAULT #{connection.quote(column.default)}"
    end
    fragment += ' NOT NULL' unless column.null
    fragment
  end

  # Partitions for the months the existing rows fall in.
  #
  # Existing data can be far older than the retention window, and copying a row
  # with no matching partition raises CheckViolation. Creating one partition per
  # month of history is what keeps the conversion non-destructive: old rows are
  # preserved and the retention job drops them on its next run.
  def self.partitions_for_existing_rows(source_table, new_table, prefix)
    range = execute(
      "SELECT MIN(generated) AS first, MAX(generated) AS last FROM #{quote(source_table)}"
    ).first
    return [] if range.nil? || range['first'].nil?
    ensure_partitions_covering(new_table, range['first'].to_date, range['last'].to_date, prefix: prefix)
  end

  def self.copy_rows(source_table, new_table, columns)
    quoted = columns.map { |c| ActiveRecord::Base.connection.quote_column_name(c) }.join(', ')
    execute("INSERT INTO #{quote(new_table)} (#{quoted}) " \
            "SELECT #{quoted} FROM #{quote(source_table)}")
  end

  # events_id_seq is OWNED BY events.id, so it must be re-pointed at the twin
  # before the original is dropped, or the dependency takes the sequence down with
  # it and inserts lose their id default.
  #
  # The copy inserted explicit ids, which does not advance the sequence; without
  # setval a later insert that relies on the default reuses an existing id.
  def self.repoint_sequence(table, new_table)
    sequence = "#{table}_id_seq"
    return unless sequence_exists?(sequence)

    quoted_col = ActiveRecord::Base.connection.quote_column_name('id')
    execute("ALTER SEQUENCE #{quote(sequence)} OWNED BY #{quote(new_table)}.#{quoted_col}")
    max = connection.select_value(
      "SELECT MAX(#{quoted_col}) FROM #{connection.quote_table_name(new_table)}"
    )
    return if max.nil?
    execute("SELECT setval(#{ActiveRecord::Base.connection.quote(sequence)}, #{max.to_i})")
  end

  def self.sequence_exists?(sequence)
    connection.select_value(
      "SELECT 1 FROM pg_class WHERE relkind = 'S' AND relname = " \
      "#{ActiveRecord::Base.connection.quote(sequence)}"
    ) == 1
  end

  def self.connection
    ActiveRecord::Base.connection
  end

  # Identifier quoting.
  #
  # Every name reaching here is built from PARTITION_PREFIXES or Date#strftime, so
  # this is defence in depth. The validation is what makes the interpolated DDL
  # provably safe: a name that is not a bare Postgres identifier is rejected
  # before it can reach a statement, rather than merely escaped.
  SAFE_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/.freeze

  def self.quote(name)
    unless name.to_s.match?(SAFE_IDENTIFIER)
      raise ArgumentError, "refusing to use #{name.inspect} as an identifier"
    end
    ActiveRecord::Base.connection.quote_table_name(name)
  end
end
