ENV["RAILS_ENV"] ||= "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

class ActiveSupport::TestCase
  ActiveRecord::Migration.check_pending!

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

# ActionController::TestCase reuses a single @request across requests in one test.
# On Rails 5.2 each new request merges cookies from two places -- @request.cookies
# and the previous request's cookie jar (Cookies#update_cookies_from_jar) -- so a
# cookie carried by an earlier request survives a plain cookies.delete on the test
# jar and silently authenticates the next request as the wrong user. Tests that
# present a specific cookie after making another request must clear both sources.
class ActionController::TestCase
  def reset_cookies!
    @request.cookies.clear
    @request.cookie_jar.instance_variable_get(:@cookies).clear
    cookies.clear
  end
end
