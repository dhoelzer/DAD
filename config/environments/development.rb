Events::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Committed so a fresh checkout boots with no setup. ENV still wins, matching
  # the precedence Rails used when this value lived in config/secrets.yml.
  # Setting it here rather than there avoids the Rails 7.1
  # "configured in Rails.application.secrets" deprecation (that path is removed
  # in 7.2). Not a secret: it signs cookies on a developer's own machine.
  config.secret_key_base = ENV["SECRET_KEY_BASE"] || '7a9d9a89be64f8d24bda2dd4199b44c67911ffa0b5967cf9fe3fe9185c2d1279'

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations
  config.active_record.migration_error = :page_load

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true
end
