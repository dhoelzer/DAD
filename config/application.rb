require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'set'

# Reopens Ruby's built-in Math module to add the four statistics helpers the
# dashboard uses (mean, variance, standard_deviation). Because this reopens the
# core module rather than defining a new one, Math.sqrt and the rest of the
# standard library remain available -- standard_deviation depends on that.

# Adding methods to a core class is a global change: it applies to every caller
# in the process, including gems. A gem that defines Math.mean would overwrite
# this one. A namespaced module would be safer.

# All four divide by values.count with no guard, so an empty array yields NaN or
# Infinity rather than 0.
module Math
  def self.standard_deviation(values=[])
    Math.sqrt(Math.variance(values))
  end
  
  def self.variance(values)
    sum = 0
    mean = Math.mean(values)
    values.each{|s| sum = sum + ((s - mean)**2)}
    sum.to_f / (values.count)
  end
  
  def self.mean(values)
    Math.sum_values(values).to_f / (values.count)
  end
  
  def self.sum_values(values)
    sum = 0
    values.each{|s| sum = sum + s}
    sum
  end
end

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
