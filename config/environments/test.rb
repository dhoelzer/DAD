Events::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Committed so `rake test`/`cucumber` and a fresh checkout need no setup. ENV
  # still wins, matching the precedence Rails used when this value lived in
  # config/secrets.yml. Setting it here rather than there avoids the Rails 7.1
  # "configured in Rails.application.secrets" deprecation (that path is removed
  # in 7.2). Not a secret: it signs cookies on a developer's own machine.
  config.secret_key_base = ENV["SECRET_KEY_BASE"] || '26dc4b4ea181d7e5850533b057b6c0399d5058f1c905c105c9322eb9d00b1d31'

  # The test environment is used exclusively to run your application's
  # test suite. You never need to work with it otherwise. Remember that
  # your test database is "scratch space" for the test suite and is wiped
  # and recreated between test runs. Don't rely on the data there!
  config.cache_classes = true

  # Rails 4.2 defaults to :sorted and warns on every run; :random is the
  # Rails 5 default and surfaces order dependencies in the fixtures.
  config.active_support.test_order = :random

  # db/schema.rb is committed in SQLite flavour, because that is the adapter
  # development and the default test run use. A `rake db:migrate` under
  # DATABASE_URL=postgres://... would otherwise rewrite it in Postgres flavour --
  # enable_extension lines, bigint instead of integer limit: 8, and (once events
  # is partitioned) PARTITION BY / PARTITION OF table options that SQLite cannot
  # load at all. The Postgres CI job migrates to exercise the real migration
  # path, so it must not be allowed to overwrite the canonical dump.
  #
  # Regenerate schema.rb deliberately, from SQLite:
  #   unset DATABASE_URL && RAILS_ENV=test bundle exec rake db:migrate
  config.active_record.dump_schema_after_migration = false

  # Related trap: Rails purges and reloads db/schema.rb before a test run when a
  # migration is newer than the dump. Under Postgres that reload installs the
  # SQLite-flavoured dump -- which cannot express PARTITION BY at all -- and
  # silently replaces whatever the migrations built. So when DATABASE_URL points
  # at Postgres, the schema comes from db/migrate (see rake
  # db:migrate_from_scratch) and Rails must not touch it.
  config.active_record.maintain_test_schema = !ENV['DATABASE_URL'].to_s.match?(%r{\Apostgres(ql)?://})

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure static asset server for tests with Cache-Control for performance.
  # Rails 5.0 renamed serve_static_files/static_cache_control to the
  # public_file_server options; the old names are silently swallowed by
  # Rails::Railtie::Configuration#method_missing, so they must be translated.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=3600" }

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Raise exceptions instead of rendering exception templates.
  # Rails 7.1 replaced the boolean with :all/:rescuable/:none; false still works
  # but warns, and :none is the exact equivalent.
  config.action_dispatch.show_exceptions = :none

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr
end
