require 'test_helper'

# Archive retention: pruning the oldest archives so the partition holding them
# keeps the free-space floor an admin configures.
#
# Pruning deletes the last copy of months the database has already dropped, so
# these tests are the safety net for the destructive half of retention. The
# filesystem size is injected rather than read from the test machine, so the
# arithmetic is checked against exact numbers; #disk_space is tested separately
# against the real filesystem.
#
# No preferences fixture: fixtures :all would load one into every test in the
# suite, and a user_id 0 row changes what the dashboard tests see. The row is
# created here and rolled back with the test transaction.
class ArchivePruningTest < ActiveSupport::TestCase
  MB = 1024 * 1024

  def setup
    @dir = Dir.mktmpdir('archive_pruning')
    @saved_dir = ENV['DAD_OFFLINE_STORAGE_DIR']
    ENV['DAD_OFFLINE_STORAGE_DIR'] = @dir
    @pref = Preference.create!(user_id: 0, created_at: Time.now, updated_at: Time.now)
  end

  def teardown
    ENV['DAD_OFFLINE_STORAGE_DIR'] = @saved_dir
    FileUtils.remove_entry(@dir) if File.directory?(@dir)
  end

  def floor(percent)
    @pref.update!(archiveFreeSpacePercent: percent)
  end

  # Writes an archive for month +yyyymm+ (e.g. '202501') of +bytes+ size, under
  # the named table's partition prefix (e.g. 'events').
  def archive(table, yyyymm, bytes)
    path = File.join(@dir, "#{EventPartitioning::PARTITION_PREFIXES.fetch(table)}#{yyyymm}#{EventPartitionBackup::ARCHIVE_SUFFIX}")
    File.binwrite(path, 'x' * bytes)
    path
  end

  def archived_names
    Dir.children(@dir).select { |f| f.end_with?(EventPartitionBackup::ARCHIVE_SUFFIX) }.sort
  end

  # --- the setting ------------------------------------------------------------

  test 'pruning is disabled when no free-space floor is configured' do
    assert_nil EventPartitionBackup.free_space_percent

    archive('events', '202501', 10 * MB)
    result = EventPartitionBackup.prune_archives(disk: [100 * MB, 1 * MB])

    assert_empty result[:deleted]
    assert_match(/pruning disabled/, result[:error])
    assert_equal 1, archived_names.size, 'nothing may be deleted while the floor is unset'
  end

  test 'a zero floor disables pruning rather than meaning keep nothing free' do
    floor(0)
    assert_nil EventPartitionBackup.free_space_percent
  end

  test 'the floor is read back from the global preference row' do
    floor(25)
    assert_equal 25, EventPartitionBackup.free_space_percent
  end

  # Out-of-range input is the dangerous case: 1000 read literally means "keep
  # 1000% of the partition free", which no filesystem can satisfy, so pruning
  # would delete every archive on disk.
  test 'an out-of-range floor is clamped to 100 on write' do
    @pref.archiveFreeSpacePercent = 1000
    assert_equal 100, @pref.archiveFreeSpacePercent
    floor(1000)
    assert_equal 100, EventPartitionBackup.free_space_percent
  end

  test 'a negative floor is clamped to zero' do
    @pref.archiveFreeSpacePercent = -5
    assert_equal 0, @pref.archiveFreeSpacePercent
  end

  test 'a blank floor stays nil' do
    @pref.archiveFreeSpacePercent = ''
    assert_nil @pref.archiveFreeSpacePercent
  end

  # --- the arithmetic ---------------------------------------------------------

  test 'nothing is pruned while the floor already holds' do
    archive('events', '202501', 10 * MB)
    # 100MB total, 50MB free, 10% floor = 10MB required: 40MB of headroom.
    result = EventPartitionBackup.prune_archives(percent: 10, disk: [100 * MB, 50 * MB])
    assert_empty result[:deleted]
    assert_nil result[:error]
    assert_equal 1, archived_names.size
  end

  test 'the oldest archive is deleted first, and only as many as needed' do
    oldest = archive('events', '202401', 10 * MB)
    middle = archive('events', '202501', 10 * MB)
    newest = archive('events', '202601', 10 * MB)

    # 100MB total, 12MB free, 20% floor = 20MB required: 8MB short, so one
    # 10MB archive has to go.
    result = EventPartitionBackup.prune_archives(percent: 20, disk: [100 * MB, 12 * MB])

    assert_equal [oldest], result[:deleted]
    assert_equal 10 * MB, result[:bytes]
    assert archived_names.include?(File.basename(middle))
    assert archived_names.include?(File.basename(newest))
    refute archived_names.include?(File.basename(oldest))
  end

  test 'archives are ordered by the month in their name, not by mtime' do
    oldest = archive('events', '202401', 10 * MB)
    archive('events', '202501', 10 * MB)
    # A hand-copied archive gets a fresh mtime; pruning by mtime would delete
    # 202501 and keep the oldest history.
    File.utime(Time.now, Time.now, oldest)

    result = EventPartitionBackup.prune_archives(percent: 20, disk: [100 * MB, 12 * MB])
    assert_equal [oldest], result[:deleted],
      'the oldest month must be pruned even when its mtime is the newest'
  end

  test 'both partitioned tables are pruned together, oldest month first overall' do
    old_words = archive('events_words', '202401', 10 * MB)
    old_events = archive('events', '202402', 10 * MB)

    result = EventPartitionBackup.prune_archives(percent: 30, disk: [100 * MB, 12 * MB])
    assert_equal [old_words, old_events], result[:deleted]
    assert_empty archived_names
  end

  # The point of pruning before archiving: room has to exist for the archive
  # about to be written, not just for the ones already on disk.
  test 'needed_bytes is charged against the floor, so room is made before writing' do
    oldest = archive('events', '202401', 10 * MB)
    archive('events', '202501', 10 * MB)

    # Free space alone satisfies the floor (12MB free vs 10MB required, 2MB of
    # headroom), but a 5MB archive is incoming, so one month must go first.
    comfortable = EventPartitionBackup.prune_archives(percent: 10, disk: [100 * MB, 12 * MB])
    assert_empty comfortable[:deleted], 'sanity: without the incoming write, nothing is due'

    result = EventPartitionBackup.prune_archives(percent: 10, needed_bytes: 5 * MB,
                                                disk: [100 * MB, 12 * MB])
    assert_equal [oldest], result[:deleted]
  end

  test 'dry_run reports the same selection without deleting anything' do
    oldest = archive('events', '202401', 10 * MB)
    archive('events', '202501', 10 * MB)

    result = EventPartitionBackup.prune_archives(percent: 20, dry_run: true,
                                                disk: [100 * MB, 12 * MB])
    assert_equal [oldest], result[:deleted]
    assert_equal 2, archived_names.size, 'dry run must not delete'
  end

  # --- fail-closed behaviour --------------------------------------------------

  test 'an unmeasurable filesystem prunes nothing' do
    archive('events', '202401', 10 * MB)
    result = EventPartitionBackup.prune_archives(percent: 20, disk: [nil, nil])

    assert_empty result[:deleted]
    assert_match(/cannot measure/, result[:error])
    assert_equal 1, archived_names.size, 'a bad reading must not delete history'
  end

  test 'df output is parsed into total and free bytes' do
    total, free = EventPartitionBackup.disk_space(@dir)
    assert total.positive?, 'expected a real filesystem total'
    assert free.positive?, 'expected a real filesystem free count'
    assert free <= total
  end

  test 'df on a nonexistent path reports unmeasurable rather than raising' do
    assert_nil EventPartitionBackup.disk_space(File.join(@dir, 'no-such-dir'))
  end

  # When every archive is gone and the floor still cannot be met, the caller has
  # to be told: retention is about to fail for lack of space.
  test 'a floor that cannot be met reports the shortfall' do
    only = archive('events', '202401', 10 * MB)
    # 100MB total, 1MB free, 50% floor = 50MB required; 10MB is all there is.
    result = EventPartitionBackup.prune_archives(percent: 50, disk: [100 * MB, 1 * MB])

    assert_equal [only], result[:deleted]
    assert_empty archived_names
    assert result[:short].to_i > 0, 'must report still being short'
  end

  # --- what is prunable -------------------------------------------------------

  test 'files that are not our archives are never deleted' do
    stray = File.join(@dir, 'notes.csv')
    keep = File.join(@dir, 'not_an_archive_p202401.csv')
    File.write(stray, 'x' * 10)
    File.write(keep, 'x' * 10)
    archive('events', '202401', 10 * MB)

    result = EventPartitionBackup.prune_archives(percent: 90, disk: [100 * MB, 1 * MB])

    deleted = result[:deleted].map { |p| File.basename(p) }
    refute_includes deleted, 'notes.csv'
    refute_includes deleted, 'not_an_archive_p202401.csv'
    assert File.file?(stray)
    assert File.file?(keep)
  end

  test 'a .part file from an interrupted archive is not treated as an archive' do
    half = File.join(@dir, "events_p202401#{EventPartitionBackup::ARCHIVE_SUFFIX}.part")
    File.write(half, 'x' * 10)
    assert_empty EventPartitionBackup.archives(@dir)
  end

  test 'archives lists path, size and month' do
    path = archive('events', '202503', 1234)
    listed = EventPartitionBackup.archives(@dir)
    assert_equal 1, listed.size
    assert_equal path, listed.first[0]
    assert_equal 1234, listed.first[1]
    assert_equal Date.new(2025, 3, 1), listed.first[2]
  end

  # --- size projection --------------------------------------------------------

  test 'the incoming size estimate uses the largest recent archive' do
    archive('events', '202401', 1 * MB)
    archive('events', '202501', 9 * MB)
    archive('events', '202601', 4 * MB)
    assert_equal 9 * MB, EventPartitionBackup.estimated_archive_bytes(@dir)
  end

  test 'the incoming size estimate is zero with no archives' do
    assert_equal 0, EventPartitionBackup.estimated_archive_bytes(@dir)
  end

  test 'upcoming_archive_bytes falls back to the estimate when sizes are unavailable' do
    archive('events', '202501', 7 * MB)
    # A partition that does not exist measures zero, so the estimate is used.
    bytes = EventPartitionBackup.upcoming_archive_bytes(['events_p209901'], @dir)
    assert_equal 7 * MB, bytes
  end

  # --- what must NOT be pruned -------------------------------------------------

  # The failure this prevents: pruning frees bytes for an archive the very next
  # step re-writes, so the run reports a successful prune and the floor is still
  # breached. Net-zero churn, and it destroys nothing, but the arithmetic lies.
  test 'archives for partitions about to be archived are not pruned' do
    about_to_write = archive('events', '202401', 10 * MB)
    older = archive('events', '202301', 10 * MB)

    result = EventPartitionBackup.prune_archives(percent: 20, disk: [100 * MB, 12 * MB],
                                                protected: ['events_p202401'])
    assert_equal [older], result[:deleted],
      'the archive this run is about to write must not be the one it deletes'
    assert File.file?(about_to_write)
  end

  test 'protecting every archive leaves nothing prunable and reports the shortfall' do
    keep = archive('events', '202401', 10 * MB)
    result = EventPartitionBackup.prune_archives(percent: 50, disk: [100 * MB, 1 * MB],
                                                protected: ['events_p202401'])
    assert_empty result[:deleted]
    assert File.file?(keep)
    assert result[:short].to_i > 0, 'must report the floor as unmeetable, not silently succeed'
  end

  test 'protected accepts names for archives that do not exist' do
    older = archive('events', '202301', 10 * MB)
    result = EventPartitionBackup.prune_archives(percent: 20, disk: [100 * MB, 12 * MB],
                                                protected: ['events_p209901'])
    assert_equal [older], result[:deleted]
  end

  # An archive whose partition was restored is regenerable from the live
  # partition, so deleting it does free real space. It is not in expired_names,
  # so it must stay prunable.
  test 'an archive for a restored partition is still prunable' do
    restored = archive('events', '202401', 10 * MB)
    result = EventPartitionBackup.prune_archives(percent: 20, disk: [100 * MB, 12 * MB],
                                                protected: [])
    assert_equal [restored], result[:deleted]
  end

  # --- needed_bytes must only charge for writes that will actually happen ------

  test 'already-archived partitions are not charged as incoming bytes' do
    archive('events', '202401', 7 * MB)
    # 202401 already has an archive, so backup_partition will not re-write it.
    assert_equal 0, EventPartitionBackup.upcoming_archive_bytes(['events_p202401'], @dir)
  end

  test 'only unarchived partitions are charged' do
    archive('events', '202401', 7 * MB)
    bytes = EventPartitionBackup.upcoming_archive_bytes(
      ['events_p202401', 'events_p209901'], @dir
    )
    assert_equal 7 * MB, bytes, 'one archived (free) plus one pending (estimated)'
  end

  # A .part file is an interrupted write, so it is neither a completed archive
  # (the partition still needs archiving) nor a usable size estimate.
  test 'a .part file is not an existing archive and not an estimate source' do
    File.write(File.join(@dir, "events_p202401#{EventPartitionBackup::ARCHIVE_SUFFIX}.part"),
               'x' * 7 * MB)
    refute EventPartitionBackup.archived?('events_p202401', dir: @dir)
    assert_equal 0, EventPartitionBackup.estimated_archive_bytes(@dir)
    assert_equal 0, EventPartitionBackup.upcoming_archive_bytes(['events_p202401'], @dir)
  end

  test 'a completed archive still counts when a .part file is also present' do
    File.write(File.join(@dir, "events_p202401#{EventPartitionBackup::ARCHIVE_SUFFIX}.part"),
               'x' * 7 * MB)
    archive('events', '202501', 5 * MB)
    assert EventPartitionBackup.archived?('events_p202501', dir: @dir)
    refute EventPartitionBackup.archived?('events_p202401', dir: @dir)
    assert_equal 5 * MB, EventPartitionBackup.upcoming_archive_bytes(['events_p202401'], @dir)
  end

  test 'partition_sizes returns zero for an empty list' do
    assert_equal 0, EventPartitionBackup.partition_sizes([])
  end

  if EventPartitioning.supported?
    # pg_relation_size, not pg_total_relation_size: the CSV carries rows only, so
    # counting indexes would over-estimate and delete more history than needed.
    test 'partition_sizes measures real partitions on Postgres' do
      scratch = 'events_p209812'
      EventPartitioning.execute_partition('events', 'events_p', Date.new(2098, 12, 1))
      begin
        200.times do
          EventPartitioning.execute(
            "INSERT INTO #{scratch} (hunks, generated) VALUES ('prune size probe', '2098-12-05 00:00:00')"
          )
        end
        bytes = EventPartitionBackup.partition_sizes([scratch])
        assert bytes.positive?, 'expected a measured size for a populated partition'

        measured = EventPartitionBackup.upcoming_archive_bytes([scratch], @dir)
        assert_equal bytes, measured, 'a measured partition must not fall back to an estimate'
      ensure
        EventPartitioning.execute("DROP TABLE IF EXISTS #{scratch}")
      end
    end

    # The wiring, not the arithmetic: maintain must consult the floor and surface
    # an unmeetable one as an Alert.
    test 'maintain acts on a breached floor and alerts once' do
      total, free = EventPartitionBackup.disk_space(@dir)
      # A floor just above current free space, with nothing on disk to delete:
      # the shortfall must be reported rather than silently ignored.
      percent = [((free + 1) * 100 / total) + 1, 95].min
      @pref.update!(archiveFreeSpacePercent: percent)

      alerts_before = Alert.count
      result = EventPartitioning.prune_archives_before_archive(['events_p209901'])
      assert result[:short].to_i.positive? || result[:deleted].any?,
        'maintain must act on a breached floor'
      assert_equal alerts_before + 1, Alert.count,
        'an unmeetable floor must raise exactly one alert'
      assert Alert.exists?(short_description: "Archive space floor unmeetable (#{@dir})")
    end

    test 'the archive-space alert is not duplicated across runs' do
      @pref.update!(archiveFreeSpacePercent: 95)
      EventPartitioning.prune_archives_before_archive(['events_p209901'])
      first = Alert.count
      EventPartitioning.prune_archives_before_archive(['events_p209901'])
      assert_equal first, Alert.count, 'a daily job must not raise the same alert twice'
    end
  end
end
