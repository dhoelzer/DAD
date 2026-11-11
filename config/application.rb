require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'set'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(:default, Rails.env)

# The Rails application itself. The name is only a namespace, but it is also the
# constant the boot process expects: config.ru references Events::Application.
module Events
  # Application configuration. Beyond the usual Rails settings this does one unusual
  # thing that several other parts of the app depend on: it eagerly requires every
  # file under app/models and records the resulting subclass names in the global
  # +$_models+.
  #
  # The nav-bar layout iterates +$_models+ and calls +hidden?+ on each, which is why
  # every model must define that method. Note the requires are wrapped in a bare
  # rescue, so a model that fails to load is skipped silently and simply disappears
  # from the nav bar; and because subclasses are enumerated at boot, a model loaded
  # later is never added.
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Active Record encryption key for WindowsTarget#password.
    #
    # A WinRM password is a domain credential, so it is stored encrypted rather
    # than in the clear, where it would sit in every pg_dump, backup and replica.
    #
    # Set here rather than in an initializer: Rails reads this config from its own
    # active_record.encryption initializer, which runs before anything in
    # config/initializers/. An initializer is too late and the model raises
    # "Missing Active Record encryption credential" on first use.
    #
    # Same convention as secret_key_base: production reads from the environment
    # and fails closed rather than falling back to a committed value; development
    # and test carry committed values that are documented as dev-only.
    #
    # Changing this key makes stored Windows credentials unreadable, so generate it
    # once. Rails requires a 32-byte key.
    # Rails 8.1 needs both: primary_key for the ciphertext, and
    # key_derivation_salt because the derived-secret-key provider is armed by
    # default and raises on boot without it.
    if Rails.env.production?
      key = ENV['DAD_AR_ENCRYPTION_KEY']
      salt = ENV['DAD_AR_ENCRYPTION_SALT']
      if key.blank? || salt.blank?
        raise 'Refusing to boot in production: DAD_AR_ENCRYPTION_KEY and ' \
              'DAD_AR_ENCRYPTION_SALT must both be set. Generate them with ' \
              '`rails runner "puts SecureRandom.hex(32); puts SecureRandom.hex(32)"` ' \
              'and add them to /etc/DAD/environment. Without them, Windows ' \
              'credentials cannot be stored. See "The Windows credential keys" in README.md.'
      end
      config.active_record.encryption.primary_key = key
      config.active_record.encryption.key_derivation_salt = salt
    else
      # Not a secret: a developer's own database and the test database.
      # Introduced 2026-11-11 alongside the Windows polling feature.
      config.active_record.encryption.primary_key =
        'a3f1c6d8e9b7402516c8d4a7e2f9b1c3057d8ea46c1f9b2d7e4a8c3f60b5d291'
      config.active_record.encryption.key_derivation_salt =
        '5c7e2a91b4d83f06e8a1c9d72b6f4e30a8d5c1e97b3f6a2d4e8c0b5917a6d3f2'
    end

    # No `config.load_defaults` call, deliberately -- still correct on Rails 6.1.
    # With no call the app keeps the 4.1-era framework defaults, which is what it
    # was written against. Opting in would flip belongs_to_required_by_default to
    # true (19 belongs_to associations here have nullable foreign keys that
    # legitimately hold nil -- see RECOMMENDATIONS.md 5.2 item 6), would change
    # per-form CSRF tokens and button_to markup, and would arm
    # ActionDispatch::HostAuthorization (new in 6.0) against an empty config.hosts,
    # 403ing every request. Adopt it as its own reviewed change, not as a side
    # effect of a version bump.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    # Rails 7.1 warns that the 6.1 cache serialization format -- the default for
    # any app that predates 7.1, which this one does -- stops being supported in
    # 7.2. Nothing in the app reads or writes Rails.cache, so opting into the 7.0
    # format is free here and keeps the boot log clean.
    config.active_support.cache_format_version = 7.0

    # Date/Time#to_time used to be overridden by ActiveSupport to reproduce
    # pre-Ruby 2.4 behaviour (convert to *local system* time). Rails 8.1 removed
    # that override and the config.active_support.to_time_preserves_timezone
    # switch with it: to_time now always preserves the receiver's own zone. The
    # app never calls to_time in app/ or lib/, and both Time.zone and the system
    # zone are UTC, so the change is inert here.

    Dir[Rails.root.to_s + '/app/models/**/*.rb'].each do |file| 
      begin
        require file
      rescue => e
        # A model that fails to load is missing from $_models, so its nav-bar tab
        # silently disappears -- which reads like a routing or permissions
        # problem. Logged rather than raised: one broken model should not stop
        # the app booting, but it must not be invisible either.
        warn "DAD: failed to load model #{file}: #{e.class}: #{e.message}"
      end
    end

    $_models = ActiveRecord::Base.subclasses.collect { |type| type.name }.sort

    
  end
end
