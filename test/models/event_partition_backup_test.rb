require 'test_helper'
require 'tmpdir'

# Covers EventPartitionBackup: where archives land, what they contain, and that
# a completed archive is what gates a retention drop (RECOMMENDATIONS: no backup
# story for a retention policy that DROPs whole months).
#
# The archive is a client-side COPY, so the Postgres tests exercise the real
# path end to end: real partitioned tables, real rows, real CSV on disk, and a
# restore that reads it back.
class EventPartitionBackupTest < ActiveSupport::TestCase
  POSTGRES = ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'.freeze

  SCRATCH = 'partition_scratch'.freeze
  SCRATCH_PREFIX = 'partition_scratch_p'.freeze
  SCRATCH_PREFIXES = { SCRATCH => SCRATCH_PREFIX }.freeze

  setup do
    @dir = Dir.mktmpdir('offline_storage_test')
    @old_dir_env = ENV['DAD_OFFLINE_STORAGE_DIR']
    ENV['DAD_OFFLINE_STORAGE_DIR'] = @dir
  end

  teardown do
    ENV.delete('DAD_OFFLINE_STORAGE_DIR')
    ENV['DAD_OFFLINE_STORAGE_DIR'] = @old_dir_env if @old_dir_env
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
    EventPartitioning.execute("DROP TABLE IF EXISTS #{SCRATCH} CASCADE") if POSTGRES
  end

  def create_scratch
    EventPartitioning.execute(
      "CREATE TABLE #{SCRATCH} (id serial, generated timestamp not null, hunks text) " \
      'PARTITION BY RANGE (generated)')
    EventPartitioning.ensure_partitions(tables: [SCRATCH], today: Date.new(2026, 10, 16),
                                        prefixes: SCRATCH_PREFIXES)
  end

  def insert_scratch(generated, hunks)
    quote = EventPartitioning.connection.method(:quote)
    EventPartitioning.execute(
      "INSERT INTO #{SCRATCH} (generated, hunks) VALUES (#{quote.call(generated)}, #{quote.call(hunks)})")
  end

  # --- storage_dir (adapter-independent) --------------------------------------

  test 'storage_dir defaults to offline_storage under Rails.root' do
    ENV.delete('DAD_OFFLINE_STORAGE_DIR')
    assert_equal Rails.root.join('offline_storage').to_s, EventPartitionBackup.storage_dir
  end

  # Same systemd `KEY=` case as retention: an empty value must fall back rather
  # than resolve to Rails.root itself, which would scatter archives into the app
  # tree and make every partition look archived by accident.
  test 'an empty storage dir falls back to the default' do
    ENV['DAD_OFFLINE_STORAGE_DIR'] = ''
    assert_equal Rails.root.join('offline_storage').to_s, EventPartitionBackup.storage_dir
  end

  test 'storage_dir honours an absolute DAD_OFFLINE_STORAGE_DIR' do
    assert_equal @dir, EventPartitionBackup.storage_dir
  end

  test 'storage_dir resolves a relative DAD_OFFLINE_STORAGE_DIR under Rails.root' do
    ENV['DAD_OFFLINE_STORAGE_DIR'] = 'some/where'
    assert_equal Rails.root.join('some/where').to_s, EventPartitionBackup.storage_dir
  end

  # --- the archive itself (Postgres) ------------------------------------------

  test 'an archive is a CSV holding the partition rows with a header' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    insert_scratch('2026-04-03 10:00:00', 'first row')
    insert_scratch('2026-04-04 10:00:00', 'second row')

    path = EventPartitionBackup.backup_partition(SCRATCH, "#{SCRATCH_PREFIX}202604", dir: @dir)

    assert_equal File.join(@dir, "#{SCRATCH_PREFIX}202604.csv"), path
    rows = CSV.read(path)
    assert_equal %w[id generated hunks], rows.first
    assert_equal 3, rows.size, 'header plus two data rows'
    assert_includes rows.join, 'first row'
    assert_includes rows.join, 'second row'
  end

  test 'an empty partition still archives, so retention can proceed' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    path = EventPartitionBackup.backup_partition(SCRATCH, "#{SCRATCH_PREFIX}202605", dir: @dir)
    refute_nil path, 'an empty month is still a completed archive'
    assert EventPartitionBackup.archived?("#{SCRATCH_PREFIX}202605", dir: @dir)
    assert_equal 0, CSV.read(path).size - 1
  end

  test 'archiving a missing partition fails rather than raising' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    assert_nil EventPartitionBackup.backup_partition(SCRATCH, 'partition_scratch_p197001', dir: @dir)
    refute EventPartitionBackup.archived?('partition_scratch_p197001', dir: @dir)
  end

  test 'a failed archive leaves no file behind' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    blocked = File.join(@dir, 'blocked')
    File.write(blocked, 'not a directory')
    EventPartitionBackup.backup_partition(SCRATCH, "#{SCRATCH_PREFIX}202604", dir: blocked)
    refute Dir.children(@dir).any? { |f| f.include?('202604') },
      'no .csv and no leftover .part'
  end

  test 'an existing archive is not rewritten' do
    existing = File.join(@dir, "#{SCRATCH_PREFIX}202601.csv")
    File.write(existing, 'original')
    path = EventPartitionBackup.backup_partition(SCRATCH, "#{SCRATCH_PREFIX}202601", dir: @dir)
    assert_equal existing, path
    assert_equal 'original', File.read(existing)
  end

  # --- the safety property: drop is gated on archive ---------------------------

  test 'drop_expired_partitions keeps a partition whose archive fails' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    insert_scratch('2026-04-03', 'must survive')
    # Archive failure injected structurally: the target is a regular file, so
    # mkdir_p cannot create the directory. Permission bits would not fail under
    # a root test user.
    blocked = File.join(@dir, 'blocked')
    File.write(blocked, 'not a directory')

    dropped = EventPartitioning.drop_expired_partitions(
      tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 120,
      prefixes: SCRATCH_PREFIXES, dir: blocked)
    assert_equal [], dropped, 'an unarchived partition must survive retention'
    assert_equal 1, EventPartitioning.execute("select count(*) as c from #{SCRATCH}").first['c'].to_i
  end

  test 'drop_expired_partitions archives and then drops when the archive succeeds' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    insert_scratch('2026-04-03', 'archived then dropped')
    insert_scratch('2026-10-03', 'kept')

    dropped = EventPartitioning.drop_expired_partitions(
      tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 120,
      prefixes: SCRATCH_PREFIXES, dir: @dir)

    assert_includes dropped, "#{SCRATCH_PREFIX}202604"
    assert EventPartitionBackup.archived?("#{SCRATCH_PREFIX}202604", dir: @dir)
    assert_includes File.read(File.join(@dir, "#{SCRATCH_PREFIX}202604.csv")), 'archived then dropped'
    assert_equal 1, EventPartitioning.execute("select count(*) as c from #{SCRATCH}").first['c'].to_i
  end

  # The point of the whole feature: the archived rows are recoverable.
  test 'an archived partition can be restored into a recreated partition' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    insert_scratch('2026-04-03 10:00:00', 'recoverable row')
    insert_scratch('2026-04-04 10:00:00', 'second recoverable row')
    partition = "#{SCRATCH_PREFIX}202604"

    path = EventPartitionBackup.backup_partition(SCRATCH, partition, dir: @dir)
    EventPartitioning.execute("DROP TABLE #{partition}")
    assert_equal 0, EventPartitioning.execute("select count(*) as c from #{SCRATCH}").first['c'].to_i

    EventPartitioning.execute_partition(SCRATCH, SCRATCH_PREFIX, Date.new(2026, 4, 1))
    restored = EventPartitionBackup.restore_partition(path, partition)

    assert_equal 2, restored
    rows = EventPartitioning.execute("select hunks from #{SCRATCH} order by hunks").to_a
    assert_equal ['recoverable row', 'second recoverable row'], rows.map { |r| r['hunks'] }
  end

  # Log lines are full of commas, quotes and embedded newlines; CSV has to
  # round-trip them or the archive is silently wrong.
  test 'awkward log text survives the archive and restore' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    awkward = %Q{host, "quoted" field, line1\nline2, tab\there}
    insert_scratch('2026-04-05 10:00:00', awkward)
    partition = "#{SCRATCH_PREFIX}202604"

    path = EventPartitionBackup.backup_partition(SCRATCH, partition, dir: @dir)
    EventPartitioning.execute("DROP TABLE #{partition}")
    EventPartitioning.execute_partition(SCRATCH, SCRATCH_PREFIX, Date.new(2026, 4, 1))
    EventPartitionBackup.restore_partition(path, partition)

    got = EventPartitioning.execute("select hunks from #{SCRATCH}").first['hunks']
    assert_equal awkward, got, 'CSV must round-trip commas, quotes and newlines'
  end

  test 'expired_partitions names what would be dropped without touching anything' do
    skip 'requires PostgreSQL' unless POSTGRES
    create_scratch
    insert_scratch('2026-04-03', 'expired')
    insert_scratch('2026-10-03', 'current')
    expired = EventPartitioning.expired_partitions(
      tables: [SCRATCH], today: Date.new(2026, 10, 16), keep_days: 120, prefixes: SCRATCH_PREFIXES)
    assert_includes expired, "#{SCRATCH_PREFIX}202604"
    refute_includes expired, "#{SCRATCH_PREFIX}202610"
    refute_includes expired, "#{SCRATCH_PREFIX}default"
    assert_equal 2, EventPartitioning.execute("select count(*) as c from #{SCRATCH}").first['c'].to_i
  end
end
