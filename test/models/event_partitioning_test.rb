require 'test_helper'

# Guards monthly partitioning of events/events_words and the retention that goes
# with it (RECOMMENDATIONS.md 3.2).
#
# Partitioning is Postgres-only -- dev and test run SQLite -- so the tests split
# in two. The naming, retention-window and adapter-guard rules are pure and run
# on either engine. Anything that touches real partitions skips on SQLite, and a
# Postgres CI run exercises those against the engine that ships to production.
#
# The conversion tests build their own scratch tables rather than relying on the
# real events table being partitioned, because the interesting case is converting
# a table that already holds rows: that is what an existing install looks like,
# and it is where the data-preservation hazards live (sequence ownership, index
# name collisions, rows with no matching partition).
class EventPartitioningTest < ActiveSupport::TestCase
  POSTGRES = ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'.freeze

  SCRATCH = 'partition_scratch'.freeze
  SCRATCH_PREFIX = 'partition_scratch_p'.freeze
  # The real table list is frozen; scratch tests pass their own prefix map.
  SCRATCH_PREFIXES = { SCRATCH => SCRATCH_PREFIX }.freeze

  setup do
    drop_scratch
  end

  teardown do
    drop_scratch
  end

  # --- naming and window rules: adapter-independent ---

  test 'partition names carry the month' do
    assert_equal 'events_p202610', EventPartitioning.partition_name('events_p', Date.new(2026, 10, 5))
    assert_equal 'events_words_p202601', EventPartitioning.partition_name('events_words_p', Date.new(2026, 1, 31))
  end

  # Event.approximate_count sums pg_stat_user_tables rows matching 'events_p%'.
  # If events_words partitions also matched, the dashboard total would double.
  test 'events_words partitions do not match the events partition pattern' do
    words = EventPartitioning.partition_name('events_words_p', Date.new(2026, 10, 1))
    refute words.start_with?('events_p'), "#{words} would be counted as an events partition"
  end

  test 'partition_month reads the month back out of the name' do
    assert_equal Date.new(2026, 10, 1), EventPartitioning.partition_month('events_p202610', 'events_p')
    assert_equal Date.new(2025, 12, 1), EventPartitioning.partition_month('events_words_p202512', 'events_words_p')
  end

  test 'partition_month returns nil for the default partition and unknown names' do
    assert_nil EventPartitioning.partition_month('events_pdefault', 'events_p')
    assert_nil EventPartitioning.partition_month('events_p20261', 'events_p')
    assert_nil EventPartitioning.partition_month('events_p2026100', 'events_p')
    # A partition from the other table must not parse against this prefix.
    assert_nil EventPartitioning.partition_month('events_words_p202610', 'events_p')
  end

  test 'retention_days defaults to a year and reads the environment' do
    with_retention_env(nil) { assert_equal 365, EventPartitioning.retention_days }
    with_retention_env('30') { assert_equal 30, EventPartitioning.retention_days }
    with_retention_env('0') { assert_equal 0, EventPartitioning.retention_days }
  end

  # A systemd EnvironmentFile line written as `KEY=` produces an empty string,
  # not a missing key. Integer('') would raise and take the whole maintenance
  # job down over a blank line in a config file.
  test 'an empty retention value falls back to the default' do
    with_retention_env('') { assert_equal 365, EventPartitioning.retention_days }
    with_retention_env('  ') { assert_equal 365, EventPartitioning.retention_days }
  end

  test 'a non-numeric retention is rejected rather than silently ignored' do
    # Silently falling back to the default would keep data an operator believed
    # was being purged.
    with_retention_env('forever') do
      assert_raises(ArgumentError) { EventPartitioning.retention_days }
    end
  end

  test 'expected_months spans the retention window plus two months ahead' do
    months = EventPartitioning.expected_months(Date.new(2026, 10, 16), keep_days: 120)
    assert_equal Date.new(2026, 10, 1), months.last(3).first
    assert_equal Date.new(2026, 12, 1), months.last
    assert months.all? { |m| m.day == 1 }, 'months must be month starts'
    assert_operator months.size, :>=, 6
  end

  test 'expected_months never goes back when retention is disabled' do
    months = EventPartitioning.expected_months(Date.new(2026, 10, 16), keep_days: 0)
    assert_equal Date.new(2026, 10, 1), months.first
  end

  # A Job row that exists in a dev database must not raise an Alert every cycle.
  test 'maintain returns a summary string on either adapter' do
    # Retention pinned to 0 so the Postgres branch cannot drop partitions other
    # tests are relying on.
    with_retention_env('0') do
      summary = EventPartitioning.maintain
      assert_kind_of String, summary
      if POSTGRES
        assert_match(/partitions:/, summary)
      else
        assert_match(/Postgres-only/, summary)
      end
    end
  end

  # --- adapter guards ---

  test 'ensure_partitions refuses a non-Postgres adapter' do
    skip 'guard is Postgres-specific' if POSTGRES
    assert_raises(ArgumentError) { EventPartitioning.ensure_partitions }
    assert_raises(ArgumentError) { EventPartitioning.drop_expired_partitions }
  end

  # --- real partitions, Postgres only ---

  test 'ensure_partitions creates the expected months and is idempotent' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table

    first = EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    assert_includes first, "#{SCRATCH_PREFIX}202610"
    assert_includes first, "#{SCRATCH_PREFIX}default"

    second = EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    assert_equal [], second, 'a second pass must be a no-op: the scheduler re-runs jobs forever'
  end

  test 'rows land in the partition for their month' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)

    insert_scratch(1, Time.new(2026, 10, 3, 8, 0, 0))
    insert_scratch(2, Time.new(2026, 10, 20, 8, 0, 0))
    insert_scratch(3, Time.new(2026, 9, 15, 8, 0, 0))

    assert_equal 3, scratch_count
    assert_equal 2, partition_count("#{SCRATCH_PREFIX}202610")
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}202609")
  end

  # The DEFAULT partition is what stops one absurd timestamp from killing an
  # entire INSERT batch: the batch is a single statement, so a CheckViolation
  # loses every event in it, not just the bad one.
  test 'an out-of-range row goes to the default partition instead of raising' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)

    insert_scratch(1, Time.new(1899, 1, 1, 0, 0, 0))
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}default")
  end

  test 'drop_expired_partitions drops whole months older than the cutoff' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(2026, 10, 3))
    insert_scratch(2, Time.new(2026, 4, 3))

    dropped = EventPartitioning.drop_expired_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 120, prefixes: SCRATCH_PREFIXES, archive: false)

    assert_includes dropped, "#{SCRATCH_PREFIX}202604"
    refute_includes dropped, "#{SCRATCH_PREFIX}202610"
    assert_equal 1, scratch_count, 'only the expired month should be gone'
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}202610")
  end

  # A partition is dropped only once its whole month is past the cutoff, so the
  # current month is never touched no matter how the day-of-month falls.
  test 'drop_expired_partitions keeps the current month' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(2026, 10, 1))

    dropped = EventPartitioning.drop_expired_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 31), keep_days: 1, prefixes: SCRATCH_PREFIXES, archive: false)
    refute_includes dropped, "#{SCRATCH_PREFIX}202610"
    assert_equal 1, scratch_count
  end

  test 'drop_expired_partitions never drops the default partition' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(1899, 1, 1))

    dropped = EventPartitioning.drop_expired_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 1, prefixes: SCRATCH_PREFIXES, archive: false)
    refute_includes dropped, "#{SCRATCH_PREFIX}default"
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}default"),
      'rows the code cannot account for by month must not be deleted'
  end

  test 'retention of zero keeps every partition' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(2000, 1, 1))

    assert_equal [], EventPartitioning.drop_expired_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 0, prefixes: SCRATCH_PREFIXES, archive: false)
    assert_equal 1, scratch_count
  end

  test 'default_partition_rows reports strays so an operator can see them' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(1899, 1, 1))
    insert_scratch(2, Time.new(2026, 10, 2))

    rows = EventPartitioning.default_partition_rows(tables: [SCRATCH], prefixes: SCRATCH_PREFIXES)
    assert_equal 1, rows[SCRATCH]
  end

  # --- converting an existing populated table, Postgres only ---

  test 'conversion preserves rows, ids and column definitions' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_unpartitioned_scratch
    insert_plain_scratch(1, Time.new(2026, 1, 15, 10, 0, 0), 'first')
    insert_plain_scratch(2, Time.new(2026, 7, 20, 10, 0, 0), 'second')
    insert_plain_scratch(99, Time.new(2026, 10, 2, 10, 0, 0), 'third')

    EventPartitioning.convert_to_partitioned(SCRATCH, primary_key: %w[id generated], prefix: SCRATCH_PREFIX)

    assert EventPartitioning.partitioned?(SCRATCH)
    assert_equal 3, scratch_count
    assert_equal [1, 2, 99], scratch_ids
    assert_equal 'third', scratch_payload(99)
    # The old single table is gone, not left behind.
    refute table_exists?("#{SCRATCH}_unpartitioned")
    refute table_exists?("#{SCRATCH}_partitioned")
  end

  # Existing data can be far older than the retention window. Copying a row with
  # no matching partition raises CheckViolation and aborts the migration.
  test 'conversion creates partitions for months of existing history' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_unpartitioned_scratch
    insert_plain_scratch(1, Time.new(2020, 2, 1, 10, 0, 0), 'old')
    insert_plain_scratch(2, Time.new(2026, 10, 2, 10, 0, 0), 'recent')

    created = EventPartitioning.convert_to_partitioned(SCRATCH, primary_key: %w[id generated], prefix: SCRATCH_PREFIX)

    assert_includes created, "#{SCRATCH_PREFIX}202002"
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}202002")
    assert_equal 1, partition_count("#{SCRATCH_PREFIX}202610")
  end

  # The copy inserts explicit ids, which leaves the sequence behind. Without
  # setval, the next insert that relies on the default reuses an existing id.
  test 'conversion advances the id sequence past the copied ids' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_unpartitioned_scratch
    insert_plain_scratch(1, Time.new(2026, 10, 1, 10, 0, 0), 'a')
    insert_plain_scratch(500, Time.new(2026, 10, 2, 10, 0, 0), 'b')

    EventPartitioning.convert_to_partitioned(SCRATCH, primary_key: %w[id generated], prefix: SCRATCH_PREFIX)

    inserted = insert_scratch_with_default_id(Time.new(2026, 10, 3, 10, 0, 0), 'c')
    assert_operator inserted, :>, 500, 'default id must not collide with a copied id'
  end

  # events_id_seq is OWNED BY events.id. If the original table is dropped while
  # it still owns the sequence, the sequence goes with it and inserts lose their
  # id default.
  test 'conversion leaves the id sequence owned by the partitioned table' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_unpartitioned_scratch
    insert_plain_scratch(1, Time.new(2026, 10, 1, 10, 0, 0), 'a')

    EventPartitioning.convert_to_partitioned(SCRATCH, primary_key: %w[id generated], prefix: SCRATCH_PREFIX)

    assert_equal SCRATCH, sequence_owner_table("#{SCRATCH}_id_seq")
  end

  # Rails' #indexes does not report the primary key's index. Missing it makes
  # creating the twin's PRIMARY KEY fail with "relation ..._pkey already exists".
  test 'conversion keeps the original index names on the partitioned table' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_unpartitioned_scratch
    insert_plain_scratch(1, Time.new(2026, 10, 1, 10, 0, 0), 'a')

    EventPartitioning.convert_to_partitioned(SCRATCH, primary_key: %w[id generated], prefix: SCRATCH_PREFIX)

    index_names = scratch_index_names
    assert_includes index_names, "#{SCRATCH}_pkey"
    assert_includes index_names, "#{SCRATCH}_payload_idx"
    assert_includes index_names, "#{SCRATCH}_generated_idx"
    assert_equal "#{SCRATCH}_pkey", primary_key_index_name(SCRATCH)
  end

  test 'conversion is a no-op on an already partitioned table' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch_table
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16), prefixes: SCRATCH_PREFIXES)
    insert_scratch(1, Time.new(2026, 10, 1, 10, 0, 0))

    assert_equal [], EventPartitioning.convert_to_partitioned(SCRATCH, prefix: SCRATCH_PREFIX)
    assert_equal 1, scratch_count
  end

  # A table with no id column (events_words) must convert without any sequence
  # or primary-key handling.
  test 'conversion handles a table with no id column' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_idless_scratch
    execute_sql("INSERT INTO #{SCRATCH} (payload, generated) VALUES ('a', '2026-10-01 10:00:00')")
    execute_sql("INSERT INTO #{SCRATCH} (payload, generated) VALUES ('b', '2026-09-01 10:00:00')")

    EventPartitioning.convert_to_partitioned(SCRATCH, prefix: SCRATCH_PREFIX)

    assert EventPartitioning.partitioned?(SCRATCH)
    assert_equal 2, scratch_count
  end

  # The real events table: the app's identity for an event is id alone, so the
  # model must keep id even though the database constraint is (id, generated).
  test 'Event keeps id as a scalar primary key' do
    assert_equal 'id', Event.primary_key
    event = Event.order(:id).first
    assert_kind_of Integer, event.id, 'a composite primary key would make #id an array'
    assert_equal event.id.to_s, event.to_param
    assert_equal event.id, Event.find(event.id).id
  end

  test 'the real events tables are partitioned under Postgres' do
    skip 'requires PostgreSQL' unless POSTGRES
    assert EventPartitioning.partitioned?('events')
    assert EventPartitioning.partitioned?('events_words')
  end

  # approximate_count sums pg_stat_user_tables rows matching 'events_p%'. If the
  # events_words partitions matched that pattern the dashboard total would be
  # inflated by every word row.
  test 'approximate_count excludes the events_words partitions' do
    skip 'requires PostgreSQL' unless POSTGRES
    Event.connection.execute('ANALYZE events')
    Event.connection.execute('ANALYZE events_words')

    events_sum = EventPartitioning.connection
      .execute("select coalesce(sum(n_live_tup),0) as s from pg_stat_user_tables where relname like 'events_p%'")
      .first['s'].to_i
    words_sum = EventPartitioning.connection
      .execute("select coalesce(sum(n_live_tup),0) as s from pg_stat_user_tables where relname like 'events_words_p%'")
      .first['s'].to_i
    assert_equal events_sum, Event.approximate_count
    # The prefixes must not overlap (the naming test pins that); here the check is
    # that the figure tracks event rows and is not inflated by the larger
    # events_words table.
    assert_operator Event.approximate_count, :<=, Event.count + words_sum,
      'approximate_count must not silently include events_words rows'
    assert_operator words_sum, :>=, 0
  end

  private

  def with_retention_env(value)
    original = ENV['DAD_EVENT_RETENTION_DAYS']
    if value.nil? then ENV.delete('DAD_EVENT_RETENTION_DAYS') else ENV['DAD_EVENT_RETENTION_DAYS'] = value end
    yield
  ensure
    original.nil? ? ENV.delete('DAD_EVENT_RETENTION_DAYS') : ENV['DAD_EVENT_RETENTION_DAYS'] = original
  end

  def execute_sql(sql)
    ActiveRecord::Base.connection.execute(sql)
  end

  def drop_scratch
    return unless POSTGRES
    execute_sql("DROP TABLE IF EXISTS #{SCRATCH} CASCADE")
    execute_sql("DROP TABLE IF EXISTS #{SCRATCH}_unpartitioned CASCADE")
    execute_sql("DROP TABLE IF EXISTS #{SCRATCH}_partitioned CASCADE")
    execute_sql("DROP SEQUENCE IF EXISTS #{SCRATCH}_id_seq CASCADE")
  end

  # Already-partitioned scratch table.
  def create_scratch_table
    execute_sql(<<~SQL)
      CREATE TABLE #{SCRATCH} (
        id bigint NOT NULL,
        payload text,
        generated timestamp NOT NULL,
        PRIMARY KEY (id, generated)
      ) PARTITION BY RANGE (generated)
    SQL
  end

  # Unpartitioned scratch table with an id sequence, index and NOT NULL column --
  # the shape an existing install presents.
  def create_unpartitioned_scratch
    execute_sql("CREATE SEQUENCE #{SCRATCH}_id_seq")
    execute_sql(<<~SQL)
      CREATE TABLE #{SCRATCH} (
        id bigint NOT NULL DEFAULT nextval('#{SCRATCH}_id_seq'),
        payload text,
        note text NOT NULL DEFAULT 'unset',
        generated timestamp NOT NULL,
        PRIMARY KEY (id)
      )
    SQL
    execute_sql("ALTER SEQUENCE #{SCRATCH}_id_seq OWNED BY #{SCRATCH}.id")
    execute_sql("CREATE INDEX #{SCRATCH}_payload_idx ON #{SCRATCH} (payload)")
    execute_sql("CREATE INDEX #{SCRATCH}_generated_idx ON #{SCRATCH} (generated)")
  end

  # No id column at all, matching events_words.
  def create_idless_scratch
    execute_sql("CREATE TABLE #{SCRATCH} (payload text, generated timestamp NOT NULL)")
    execute_sql("CREATE INDEX #{SCRATCH}_generated_idx ON #{SCRATCH} (generated)")
  end

  def insert_scratch(id, generated)
    execute_sql("INSERT INTO #{SCRATCH} (id, payload, generated) VALUES (#{id}, 'p', '#{generated.to_fs(:db)}')")
  end

  def insert_plain_scratch(id, generated, payload)
    execute_sql("INSERT INTO #{SCRATCH} (id, payload, generated) VALUES (#{id}, '#{payload}', '#{generated.to_fs(:db)}')")
  end

  def insert_scratch_with_default_id(generated, payload)
    row = ActiveRecord::Base.connection.select_all(
      "INSERT INTO #{SCRATCH} (payload, generated) VALUES ('#{payload}', '#{generated.to_fs(:db)}') RETURNING id"
    ).first
    row['id'].to_i
  end

  def scratch_count
    execute_sql("SELECT count(*) AS c FROM #{SCRATCH}").first['c'].to_i
  end

  def scratch_ids
    execute_sql("SELECT id FROM #{SCRATCH} ORDER BY id").map { |r| r['id'].to_i }
  end

  def scratch_payload(id)
    execute_sql("SELECT payload FROM #{SCRATCH} WHERE id = #{id}").first['payload']
  end

  def partition_count(name)
    execute_sql("SELECT count(*) AS c FROM #{name}").first['c'].to_i
  end

  def table_exists?(name)
    !ActiveRecord::Base.connection.select_value(
      "SELECT 1 FROM pg_class WHERE relname = '#{name}'"
    ).nil?
  end

  def scratch_index_names
    ActiveRecord::Base.connection.select_all(
      "SELECT indexname FROM pg_indexes WHERE tablename = '#{SCRATCH}'"
    ).map { |r| r['indexname'] }
  end

  def primary_key_index_name(table)
    ActiveRecord::Base.connection.select_value(
      "SELECT conname FROM pg_constraint WHERE conrelid = '#{table}'::regclass AND contype = 'p'"
    )
  end

  def sequence_owner_table(sequence)
    ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT dependent.relname
      FROM pg_depend d
      JOIN pg_class seq ON seq.oid = d.objid
      JOIN pg_class dependent ON dependent.oid = d.refobjid
      WHERE seq.relname = '#{sequence}' AND d.deptype = 'a'
    SQL
  end
end
