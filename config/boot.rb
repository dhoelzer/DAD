# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' if File.exist?(ENV['BUNDLE_GEMFILE'])

# concurrent-ruby >= 1.3.5 stopped requiring 'logger' implicitly, and Rails 6.1
# expects ActiveSupport::LoggerThreadSafeLevel::Logger to already be defined when
# activesupport loads. Without this, anything that loads activesupport before
# config/application.rb (notably bin/rails) dies with
# "uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger".
require 'logger'
