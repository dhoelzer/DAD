ENV["RAILS_ENV"] ||= "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

# Rails 4.2 recycles the functional-test response between requests by calling
# #initialize again. Ruby >= 2.5 forbids re-initializing a MonitorMixin, so every
# controller test dies with ThreadError unless the monitor state is cleared first.
# Rails 5 fixed this inside actionpack; this shim backports it for the 4.2 stack.
class ActionController::TestCase
  class TestResponse < ::ActionDispatch::TestResponse
    def recycle!
      @mon_data = nil
      @mon_data_owner_object_id = nil
      initialize
    end
  end
end

class ActiveSupport::TestCase
  ActiveRecord::Migration.check_pending!

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
