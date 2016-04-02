require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'set'

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

module Events
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
