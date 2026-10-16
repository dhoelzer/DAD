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
    connection.tables.each { |table| connection.drop_table(table, force: :cascade) }
    connection.execute('DROP SEQUENCE IF EXISTS events_id_seq CASCADE')

    context = ActiveRecord::MigrationContext.new(
      File.expand_path('../../db/migrate', __dir__)
    )
    context.migrate

    puts "migrated from scratch to #{context.current_version}"
  end
end
