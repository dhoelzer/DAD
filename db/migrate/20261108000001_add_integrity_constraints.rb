# Integrity constraints the application had none of, plus the cleanup that makes
# two of them safe to add.
#
# 1. jobs.frequency gains a NOT NULL default and a CHECK. A Job with a nil
#    frequency used to save cleanly, and scheduler.rb then raised
#    `undefined method 'seconds' for nil` on the reschedule line, which sat
#    outside its begin/rescue. That killed the process; with Restart=always and
#    next_run never advanced it became a permanent crash loop, and every other
#    Job stopped running with it. A blank "Frequency" field in the form is
#    enough to cause this.
#
# 2. users.username gains a unique index. Nothing at any layer enforced
#    uniqueness, so two accounts could share a name; do_logon uses find_by, so
#    the lowest id won and the second account could never sign in, silently.
#
# 3. sessions.session_hash gains a unique index. gatekeeper resolves the
#    :sessionID cookie with find_by(session_hash:) on every authenticated
#    request, and the plan was a full table SCAN.
#
# The CHECK constraint is Postgres-only: SQLite supports CHECK in CREATE TABLE
# but not ALTER TABLE ADD CONSTRAINT, so the model validation is the only
# enforcement there. The unique indexes work on both.
class AddIntegrityConstraints < ActiveRecord::Migration[8.1]
  USER_INDEX  = 'index_users_on_username'.freeze
  SESS_INDEX  = 'index_sessions_on_session_hash'.freeze
  FREQ_CHECK  = 'jobs_frequency_positive'.freeze

  # CONCURRENTLY cannot run inside a transaction, and a plain build would lock
  # the tables the web tier writes to. Same reasoning as
  # AddPatternIndexToWords and AddSearchIndexToEventsWords.
  disable_ddl_transaction!

  def up
    normalize_job_frequencies
    normalize_usernames

    add_unique_index :users, :username, USER_INDEX
    add_unique_index :sessions, :session_hash, SESS_INDEX

    if connection.adapter_name == 'PostgreSQL'
      execute "ALTER TABLE jobs ADD CONSTRAINT #{FREQ_CHECK} CHECK (frequency IS NULL OR frequency > 0)"
    end
  end

  def down
    if connection.adapter_name == 'PostgreSQL'
      execute "ALTER TABLE jobs DROP CONSTRAINT IF EXISTS #{FREQ_CHECK}"
    end
    connection.remove_index :sessions, name: SESS_INDEX if index_named?(:sessions, SESS_INDEX)
    connection.remove_index :users,   name: USER_INDEX   if index_named?(:users,   USER_INDEX)
    change_column_default :jobs, :frequency, from: 3600, to: nil
  end

  # Rows written before this migration can hold a nil, zero or negative
  # frequency, and every one of those crashes the scheduler. Rewriting them to
  # a sane interval is the difference between "the deploy works" and "the
  # deploy crash-loops on the first row it reads".
  def normalize_job_frequencies
    execute 'UPDATE jobs SET frequency = 3600 WHERE frequency IS NULL OR frequency <= 0'
    change_column_default :jobs, :frequency, 3600
  end

  # A unique index cannot be built over duplicate or empty usernames, and
  # refusing to migrate would wedge every later deploy. So the pre-existing
  # damage is
  # repaired first, loudly, rather than silently:
  #
  #   * blank/nil usernames are given a distinct placeholder, because an account
  #     with an empty username is reachable by submitting the login form with
  #     the username field left blank.
  #   * duplicate names are suffixed with the row id, so the account that
  #     previously could not sign in becomes sign-in-able rather than being
  #     deleted. Deleting an account here would destroy an operator's work.
  #
  # An administrator sees the resulting names on the users screen and can fix
  # them; nothing is lost in the process.
  def normalize_usernames
    blank = select_all(
      "select id from users where username is null or trim(username) = '' order by id")
    blank.each do |row|
      execute "UPDATE users SET username = #{connection.quote("disabled-account-#{row['id']}")} WHERE id = #{row['id']}"
    end

    dupes = select_all(
      'select id, username from users where username in ' \
      '(select username from users where username is not null and trim(username) <> \'\' ' \
      'group by username having count(*) > 1) order by username, id')
    dupes.each do |row|
      # The lowest id keeps the name it already had; later ones become unique.
      next if row['id'] == dupes.find { |r| r['username'] == row['username'] }['id']
      renamed = "#{row['username']}-#{row['id']}"
      execute "UPDATE users SET username = #{connection.quote(renamed)} WHERE id = #{row['id']}"
    end
  end

  # Adds a unique index, tolerating the INVALID husk a failed CONCURRENTLY
  # build leaves behind (it still holds the name, so a retry would fail with
  # "already exists" and wedge the deploy).
  def add_unique_index(table, column, index_name)
    if connection.adapter_name == 'PostgreSQL'
      if (name = invalid_index_named(index_name))
        say_with_time "dropping INVALID index #{name} left by a failed CONCURRENTLY build" do
          remove_index table, name: name, algorithm: :concurrently
        end
      end
      add_index table, column, name: index_name, unique: true, algorithm: :concurrently
    else
      add_index table, column, name: index_name, unique: true
    end
  end

  # Copied reasoning from AddPatternIndexToWords: index_exists? does not filter
  # pg_index.indisvalid, so an INVALID husk reads as healthy.
  def index_named?(table, index_name)
    connection.indexes(table).any? { |i| i.name == index_name }
  end

  def invalid_index_named(index_name)
    invalid = connection.select_value(
      'select not i.indisvalid from pg_class c ' \
      'join pg_index i on i.indexrelid = c.oid ' \
      "where c.relname = #{connection.quote(index_name)} and c.relkind = 'i'")
    invalid ? index_name : nil
  end
end
