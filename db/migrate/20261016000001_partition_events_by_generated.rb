require_relative '../../app/models/event_partitioning'

# Converts events and events_words to monthly range partitions on +generated+.
#
# Postgres-only: on SQLite this is a no-op, because SQLite has no partitioning
# and dev/test run SQLite.
#
# Why: RECOMMENDATIONS.md 3.2. Both tables grew without bound, and index size,
# search latency and backup time all degrade with them. Retention becomes
# DROP TABLE on a month's partition instead of a DELETE that rewrites every
# index and leaves the space unusable until a full VACUUM.
#
# The mechanics live in EventPartitioning.convert_to_partitioned, where they can
# be tested against scratch tables; this file only decides which tables to
# convert and with what primary key. Read that method before changing anything
# here -- it explains the sequence-ownership and index-name ordering that the
# swap depends on.
#
# Two consequences worth knowing before deploying:
#
# * The swap copies every row under an exclusive lock, so on a large install
#   schedule a maintenance window.
# * events moves from PRIMARY KEY (id) to PRIMARY KEY (id, generated), because a
#   partitioned table's key must contain the partition key. Event pins
#   self.primary_key = 'id' so the app keeps treating id alone as the identity.
class PartitionEventsByGenerated < ActiveRecord::Migration[8.1]
  # events_words has no id column at all (id: false), so it gets no primary key
  # and no sequence handling.
  def up
    return unless EventPartitioning.supported?

    EventPartitioning.convert_to_partitioned('events', primary_key: %w[id generated])
    EventPartitioning.convert_to_partitioned('events_words')
    EventPartitioning.ensure_partitions
  end

  def down
    return unless EventPartitioning.supported?

    raise ActiveRecord::IrreversibleMigration,
      'un-partitioning events/events_words is not provided: the partitioned ' \
      'tables are read by every query in the app exactly as before, so a ' \
      'rollback is not needed to keep the app working. Restore from backup if ' \
      'you truly need the original single tables back.'
  end
end
