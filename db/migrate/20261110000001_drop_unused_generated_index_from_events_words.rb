# Drops `index_events_words_on_generated`, added by 20150204125423 in 2015.
# 20261013000002's composite covering index made it unreachable.
#
# Nothing reads events_words by time alone. Event.searchSQL restricts on
# word_id and lets the planner use
# index_events_words_on_word_id_and_generated_and_event_id as a covering
# index; retention is drop-based (EventPartitioning drops whole partitions),
# not DELETE; WordsController never touches the join table. Verified on both
# engines: SQLite `EXPLAIN QUERY PLAN` reports the standalone index for none
# of the four search shapes, and on Postgres the partition child's composite
# index records idx_scan=2 while this one records idx_scan=0.
#
# What it costs to keep: 28 bytes per events_words row -- 70% the size of the
# composite index and 80% the size of the table heap itself, measured at
# 1.27M rows. events_words carries ~16 rows per event, so on an install with
# 100M index rows this is ~2.8 GB of dead index. It also has to be extended by
# every ingest: 5.1% of insert time at that scale (17.86s -> 17.00s per 100k
# lines), with no measurable change to search either way.
#
# Why NOT algorithm: :concurrently, unlike the three recent index migrations
# (20261013000002, 20261016000002, 20261108000001). Those build indexes; this
# drops one belonging to a *partitioned* table on Postgres, and Postgres refuses:
#
#   ERROR:  cannot drop partitioned index "index_events_words_on_generated" concurrently
#
# A plain DROP INDEX cascades to every partition and leaves no orphaned child
# indexes. It takes ACCESS EXCLUSIVE on the parent, so it does block ingest
# while it runs -- hence the lock_timeout below. The drop itself is not the
# problem: 3.4ms for 201k rows across 4 partitions.
class DropUnusedGeneratedIndexFromEventsWords < ActiveRecord::Migration[8.1]
  INDEX_NAME = 'index_events_words_on_generated'.freeze

  # Bounded rather than indefinite. The statement waits on any open writer
  # transaction; on a busy install that could otherwise stall ingest for as
  # long as a large batch takes to commit. Failing fast is the better outcome
  # for both: ingest keeps running, and the operator gets a clear retry
  # instead of a hung deploy. Reproduced by holding an open INSERT on
  # events_words in one session and dropping in another.
  LOCK_TIMEOUT = '5s'.freeze

  def up
    return unless connection.index_name_exists?(:events_words, INDEX_NAME)

    with_lock_timeout do
      say_with_time "dropping unused index #{INDEX_NAME}" do
        remove_index :events_words, name: INDEX_NAME
      end
    end
  end

  def down
    return if connection.index_name_exists?(:events_words, INDEX_NAME)

    with_lock_timeout do
      add_index :events_words, :generated, name: INDEX_NAME
    end
  end

  private

  # Scoped to this migration's own connection and session, so it cannot leak
  # into the rest of the run. Postgres-only: SQLite has no lock_timeout, and
  # config/database.yml already bounds its writer wait with timeout: 5000.
  def with_lock_timeout
    if connection.adapter_name == 'PostgreSQL'
      connection.execute("SET LOCAL lock_timeout = #{connection.quote(LOCK_TIMEOUT)}")
    end
    yield
  end
end
