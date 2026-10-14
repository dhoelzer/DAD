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

    # No `config.load_defaults` call, deliberately. Rails 5.2 with no call keeps
    # the 4.1-era framework defaults, which is what this app was written against;
    # opting into the 5.0 set would flip belongs_to_required_by_default to true
    # (19 belongs_to associations here have nullable foreign keys that legitimately
    # hold nil -- see RECOMMENDATIONS.md 5.2 item 6) and would change per-form CSRF
    # tokens and button_to markup. Introduce load_defaults at the Rails 6 step,
    # where it is expected, as its own reviewed change.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    Dir[Rails.root.to_s + '/app/models/**/*.rb'].each do |file| 
      begin
        require file
      rescue
      end
    end

    $_models = ActiveRecord::Base.subclasses.collect { |type| type.name }.sort

    
  end
end
