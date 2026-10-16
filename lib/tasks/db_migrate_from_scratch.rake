# Runs every migration from an empty database instead of loading db/schema.rb.
#
# Why this exists: db/schema.rb is committed in SQLite flavour (see the note in
# config/environments/test.rb). `rake db:migrate` against an empty Postgres
# database loads that dump rather than replaying db/migrate, so anything a
# migration does that the dump cannot express -- partitioning events, for one --
# never runs, and the Postgres CI job silently tests a schema production will
# never have.
#
# The Postgres CI job uses this to prove the migration chain actually works on
# the engine production runs.
namespace :db do
  desc 'Replay every migration against an empty database, ignoring db/schema.rb'
  task migrate_from_scratch: :environment do
    if Rails.env.production?
      raise 'db:migrate_from_scratch drops and rebuilds the database; refusing to run in production'
    end

    connection = ActiveRecord::Base.connection
    # Drop top-level tables only. On Postgres `tables` also lists the monthly
    # partitions, and dropping the partitioned parent cascades its partitions
    # away -- so dropping a listed partition afterwards fails on any database that
    # already has the partitioned shape, and the task only ever worked on a
    # freshly created one.
    top_level =
      if connection.adapter_name == 'PostgreSQL'
        connection.select_values(
          'select c.relname from pg_class c ' \
          'join pg_namespace n on n.oid = c.relnamespace ' \
          "where n.nspname = current_schema and c.relkind in ('r', 'p') " \
          'and not c.relispartition order by c.relname')
      else
        connection.tables
      end
    top_level.each { |table| connection.drop_table(table, force: :cascade) }
    # events_id_seq is created by the partitioning migration and outlives the
    # partitioned table it belongs to, so dropping tables alone leaves it behind
    # and the next create_sequence fails. Postgres-only: SQLite has no SEQUENCE
    # statement at all, so running this unconditionally aborts the task.
    if connection.adapter_name == 'PostgreSQL'
      connection.execute('DROP SEQUENCE IF EXISTS events_id_seq CASCADE')
    end

    context = ActiveRecord::MigrationContext.new(
      File.expand_path('../../db/migrate', __dir__)
    )
    context.migrate

    puts "migrated from scratch to #{context.current_version}"
  end
end
