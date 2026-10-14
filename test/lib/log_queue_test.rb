require 'test_helper'
require File.expand_path('../../../lib/log_queue', __FILE__)

class LogQueueTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir('logs_to_process')
    @done = Dir.mktmpdir('processed_logs')
  end

  def teardown
    [@dir, @done].each { |d| FileUtils.remove_entry(d) if d && File.directory?(d) }
  end

  def create(name)
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "line one\nline two\n")
    path
  end

  test 'pending lists files in sorted order' do
    create('b.log')
    create('a.log')
    assert_equal [File.join(@dir, 'a.log'), File.join(@dir, 'b.log')], LogQueue.pending(@dir)
  end

  # Dir.glob("*") also returns directories. The importer reads every result with
  # File.foreach, which raises IsADirectoryError, and its error path exits the
  # whole process -- so one stray directory used to stop ingestion entirely.
  test 'pending ignores directories' do
    create('good.log')
    FileUtils.mkdir_p(File.join(@dir, 'stray'))
    assert_equal [File.join(@dir, 'good.log')], LogQueue.pending(@dir)
  end

  test 'pending excludes files already claimed' do
    create('a.log')
    create('b.log')
    LogQueue.claim(File.join(@dir, 'a.log'))
    assert_equal [File.join(@dir, 'b.log')], LogQueue.pending(@dir)
  end

  test 'claim renames the file so no other pass picks it up' do
    path = create('a.log')
    in_flight = LogQueue.claim(path)

    assert_equal "#{path}.processing", in_flight
    refute File.exist?(path), 'the unclaimed name must be gone'
    assert File.exist?(in_flight), 'the contents must still be there to read'
  end

  test 'abandoned finds claimed files from a dead run' do
    create('a.log')
    LogQueue.claim(File.join(@dir, 'a.log'))
    assert_equal ["#{File.join(@dir, 'a.log')}.processing"], LogQueue.abandoned(@dir)
  end

  test 'reclaim puts abandoned files back in the queue' do
    create('a.log')
    create('b.log')
    LogQueue.claim(File.join(@dir, 'a.log'))

    reclaimed = LogQueue.reclaim(@dir)

    assert_equal ['a.log'], reclaimed
    assert_equal [File.join(@dir, 'a.log'), File.join(@dir, 'b.log')], LogQueue.pending(@dir)
  end

  # A dot inside the name must not be mistaken for the suffix.
  test 'reclaim only strips the exact suffix' do
    create('report.processing.log')
    LogQueue.claim(File.join(@dir, 'report.processing.log'))

    LogQueue.reclaim(@dir)
    assert File.exist?(File.join(@dir, 'report.processing.log'))
  end

  test 'complete moves a claimed file to the processed directory' do
    path = create('a.log')
    in_flight = LogQueue.claim(path)
    LogQueue.complete(in_flight, @done)

    refute File.exist?(in_flight)
    assert File.exist?(File.join(@done, 'a.log')), 'the file must land under its original name'
    assert_equal "line one\nline two\n", File.read(File.join(@done, 'a.log'))
  end

  test 'complete creates the processed directory when it is missing' do
    missing = File.join(@done, 'nested', 'deeper')
    in_flight = LogQueue.claim(create('a.log'))
    LogQueue.complete(in_flight, missing)
    assert File.exist?(File.join(missing, 'a.log'))
  end

  test 'a missing queue directory is empty rather than an error' do
    assert_equal [], LogQueue.pending(File.join(@dir, 'nope'))
    assert_equal [], LogQueue.abandoned(File.join(@dir, 'nope'))
  end

  # The full lifecycle: claim, read, complete, and confirm nothing is re-queued.
  test 'a completed file is never offered again' do
    path = create('a.log')
    in_flight = LogQueue.claim(path)
    LogQueue.complete(in_flight, @done)

    assert_equal [], LogQueue.pending(@dir)
    assert_equal [], LogQueue.abandoned(@dir)
  end
end
