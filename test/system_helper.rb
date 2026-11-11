require 'test_helper'
require 'capybara/dsl'
require 'capybara/minitest'

# Base class for the browser-level suite in test/system/.
#
# These tests drive the app through a real request cycle and assert on the HTML
# that comes back, which is the layer the unit and controller tests do not
# cover: the layout, the nav bar, the partials, and the asset tags. A change to
# a view can leave every controller test green and still blank the page.
#
# WHY rack-test AND NOT A REAL BROWSER
#
# The phases these tests guard change server-rendered markup and the asset
# bundle, not client behaviour. rack-test parses the rendered document, so it
# catches a broken partial, a dropped nav entry, or a renamed hook, and it runs
# anywhere the rest of the suite runs -- no browser binary, no driver, no
# network.
#
# A real browser is not currently viable in this stack, for two independent
# reasons. The app's ApplicationController#ssl filter forces http -> https
# outside development, so a browser session has to be served over TLS rather
# than driven through the in-process rack-test env. And there is no usable
# driver: chromium-driver is not installed, and the packaged candidate
# (154.0.8037.57) does not match the installed Chromium (155.0.8059.79), so
# Selenium fails at session creation. Rather than pin the suite to a
# TLS-and-driver workaround, the https requirement is satisfied the way the
# existing controller tests already satisfy it -- see
# test/controllers/authorization_test.rb, which sets HTTPS=on on the request env.
#
# Consequence, and it is a real one: rack-test does not run JavaScript. The
# dashboard's #events and #stats divs are filled by the .js.erb templates at
# runtime, so they are empty here. Assert on the static shell the server
# rendered, never on AJAX-populated content. The .js.erb output itself is
# covered by test/controllers/dashboard_render_test.rb.
class SystemTest < ActionDispatch::IntegrationTest
  include Capybara::DSL
  # Capybara::DSL gives visit/fill_in/all; the assert_* matchers come from a
  # separate module that rails' own system-test scaffolding includes for you.
  # Without it, assert_selector silently resolves to nothing and every test
  # reports "missing assertions" instead of failing.
  include Capybara::Minitest::Assertions

  setup do
    # Event/Word/Service keep row IDs in class-level caches. The transactional
    # test rollback below cannot reach them, so without this a later test would
    # resolve a word ID from a row that no longer exists -- the same reason
    # features/support/hooks.rb does this before every cucumber scenario.
    EventIngestor.resetCaches
  end

  teardown do
    reset_session!
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  # Capybara::DSL resolves relative URLs against Capybara.app_host, and the
  # scheme has to be https or the ssl filter redirects every request away from
  # the page under test. The matching HTTPS=on header is set on the driver so
  # request.protocol agrees with the URL being requested.
  Capybara.app = Rails.application
  Capybara.app_host = 'https://www.example.com'

  # rack-test is synchronous: the response is complete before visit returns.
  # Any wait is a selector that will never be satisfied, so keep it short and
  # let a genuine failure fail fast.
  Capybara.default_max_wait_time = 1

  Capybara.register_driver :dad_rack_test do |app|
    Capybara::RackTest::Driver.new(
      app,
      headers: { 'HTTPS' => 'on', 'HTTP_HOST' => 'www.example.com' }
    )
  end

  Capybara.default_driver = :dad_rack_test

  private

  # Creates a user holding every right, plus a live Session row, and presents
  # the cookie the app's gatekeeper reads. Doing it through a real logon form
  # would test the form (there is a test for that); this is for tests that just
  # need to be signed in.
  def sign_in(username: "sysuser#{Time.now.to_i}#{rand(1000)}")
    user = User.create!(username: username, attempts: 0)
    user.store_password('secretsauce')

    %w[Viewer Commentator Detective Taskmaster Admin].each do |right_name|
      right = Right.find_by(name: right_name) ||
              Right.create!(name: right_name, description: right_name)
      role = Role.find_by(name: "#{right_name}s") ||
             Role.create!(name: "#{right_name}s", description: right_name)
      role.rights << right unless role.rights.include?(right)
      user.roles << role unless user.roles.include?(role)
    end
    user.save

    session = Session.create!(user: user, expiry: Time.now + 1.hour,
                              session_hash: SecureRandom.hex(16))
    page.driver.browser.set_cookie("sessionID=#{session.session_hash}; path=/")
    user
  end

  # The nav bar is built from $_models and filtered by each model's hidden?,
  # so the set of tabs is a property of the signed-in role rather than a
  # hard-coded list.
  def nav_links
    page.all('#navbar a').map(&:text)
  end

  # Builds an event that Event.search can find, without going through
  # EventIngestor.
  #
  # Ingesting is the realistic path and is what the cucumber features use, but
  # it cannot be used here: EventIngestor writes events, systems and words from
  # background batch threads, each with its own database connection. Those
  # connections are outside the transaction that wraps a transactional-fixture
  # test, so their rows commit for real while the test's own rows roll back --
  # which leaves events whose system_id points at a system that no longer
  # exists. The next test then renders that event and _event_detail.html.erb
  # raises on nil.display_name. Same reason test/controllers/xss_test.rb builds
  # its rows by hand.
  def create_searchable_event(hunks:, tokens:, generated: Time.now)
    system = System.create!(address: '10.0.0.7', name: "sys#{Time.now.to_i}#{rand(1000)}",
                            description: 'system under test', administrator: 'ops',
                            contact_email: 'ops@example.com')
    service = Service.create!(name: "svc#{Time.now.to_i}#{rand(1000)}", description: 'service')
    event = Event.create!(system: system, service: service, generated: generated,
                          stored: generated, hunks: hunks)
    tokens.each do |token|
      word = Word.create!(text: token)
      ActiveRecord::Base.connection.execute(
        'insert into events_words (event_id, word_id, generated) ' \
        "values (#{event.id}, #{word.id}, '#{generated.to_fs(:db)}')")
    end
    event
  end
end
