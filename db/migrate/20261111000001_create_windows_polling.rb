# DAD polls Windows hosts for events over WinRM.
#
# Two tables. polling_priorities holds the tunable interval bands; windows_targets
# holds the hosts to poll and the state the adaptive scheduler needs between runs.
#
# The interval band is deliberately two-sided, because the requirement is stated
# two ways and they are not the same bound:
#
#   "Priority 1 must be polled every five minutes at a minimum"
#       -> a ceiling on the interval: never go LONGER than 300s. max_interval_secs.
#   "Systems that generate very few events should be polled less frequently,
#    but never less frequently than the minimum based on the priority"
#       -> the same ceiling, phrased as a floor on frequency.
#
# So max_interval_secs is the priority guarantee, and min_interval_secs is a
# separate guard against a busy host being polled so often that the poll itself
# becomes the load. Both are editable, and a new priority is a row rather than a
# code change, which is what "potential to add more priority levels later" asks
# for.
#
# State lives in the row, not in memory: the poller runs under Restart=always and
# a crash between polls must not reset a host's measured event rate, or every
# restart would send busy hosts back to their slowest interval.
class CreateWindowsPolling < ActiveRecord::Migration[8.1]
  # name, rank, min_interval_secs, max_interval_secs
  DEFAULT_PRIORITIES = [
    ['Priority 1', 1, 60,   300],
    ['Priority 2', 2, 300,  1_800],
    ['Priority 3', 3, 1_800, 21_600],
  ].freeze

  def change
    create_table :polling_priorities do |t|
      t.string  :name, null: false
      # Ordering only; the intervals are what the poller reads. Unique so two
      # levels cannot share a rank and make "the next priority" ambiguous.
      t.integer :rank, null: false
      t.integer :min_interval_secs, null: false
      t.integer :max_interval_secs, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :polling_priorities, :rank, unique: true
    add_index :polling_priorities, :name, unique: true

    create_table :windows_targets do |t|
      # The host to connect to. Unique: two rows for one host would double-poll
      # it and interleave two independent offset states.
      t.string  :address, null: false
      t.string  :name
      t.references :polling_priority, null: false, foreign_key: true

      # Comma-separated channel names, e.g. "Application,System,Security".
      # A plain string rather than a Postgres array so the portable schema.rb
      # and the SQLite path both hold; Windows channel names contain no commas.
      t.text :event_logs, null: false, default: 'Application,System,Setup,ForwardedEvents'

      # The disable switch. Kept separate from deleting the row: a host taken out
      # for maintenance should stop being polled without losing its measured rate,
      # its credentials, or its history.
      t.boolean :enabled, null: false, default: true

      t.string :username
      # Encrypted at rest. A WinRM password is a domain credential; in the clear
      # it would sit in every pg_dump, backup and replica.
      #
      # The column is named `password` and holds ciphertext, not a plaintext
      # mirror: Rails' `encrypts :password` reads and writes the column matching
      # the attribute name. Renaming it to password_ciphertext leaves the
      # encrypted attribute with no backing column, and saves then write nothing
      # while failing silently. text, not string, because the serialized payload
      # is longer than the credential it came from.
      t.text :password

      # Adaptive scheduling state.
      t.datetime :last_polled_at
      t.datetime :next_poll_at
      # Smoothed events-per-second, the input to the interval calculation.
      t.float  :events_per_second, null: false, default: 0.0
      t.integer :last_event_count, null: false, default: 0
      t.integer :poll_count, null: false, default: 0
      t.string :last_status

      t.timestamps
    end

    add_index :windows_targets, :address, unique: true
    # The poller's hot query: enabled targets whose next_poll_at has arrived.
    add_index :windows_targets, [:enabled, :next_poll_at]

    seed_priorities
  end

  # Seeded here rather than in db/seeds.rb so the bands exist in any database
  # built from db/migrate, which is what both compose paths do (the test suite
  # runs migrate_from_scratch, and db/schema.rb is kept in a hand-maintained
  # SQLite flavour that no environment loads -- see docker-compose.yml).
  #
  # Not in db/seeds.rb: seeds only run once, guarded by "no users yet", so a
  # later-added priority level would never reach an existing install.
  #
  # Raw SQL rather than PollingPriority.create!: migrations in this repo do not
  # reference model classes, and a model rename would otherwise break an
  # already-applied migration on replay.
  def seed_priorities
    now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
    DEFAULT_PRIORITIES.each do |name, rank, min_secs, max_secs|
      connection.execute(
        "insert into polling_priorities (name, rank, min_interval_secs, max_interval_secs, enabled, created_at, updated_at) " \
        "values (#{connection.quote(name)}, #{rank}, #{min_secs}, #{max_secs}, #{connection.quote(true)}, " \
        "#{connection.quote(now)}, #{connection.quote(now)})")
    end
  end
end
