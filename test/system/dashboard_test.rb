require 'system_helper'

# The dashboard is the landing page and the most JS-dependent view in the app.
# rack-test does not run JavaScript, so these assert on the static shell the
# server renders -- the containers the .js.erb templates fill in at runtime.
# If one of those hooks is renamed or dropped, the dashboard renders a blank
# page in a real browser while every controller test stays green; that is
# exactly what these catch. The .js.erb output itself is covered by
# test/controllers/dashboard_render_test.rb.
class DashboardTest < SystemTest
  setup do
    sign_in
  end

  test 'the dashboard renders its heading and search form' do
    visit '/'

    assert_selector 'h1', text: 'DAD Event Dashboard'
    assert_selector 'form[action="/events/search"]'
    assert_selector 'input#search_terms'
    assert_selector 'select#timeframe'
    assert_selector 'select#numresults'
    assert_selector 'input#searchload[type=submit]'
  end

  test 'the dashboard renders the containers the dashboard JS writes into' do
    visit '/'

    %w[stats events spinner updated systems_chart services_chart
       30_days_chart 7_days_chart 1_day_chart 1_hour_chart
       logging_rate insert_rate events_window recent_events].each do |id|
      assert_selector "##{id}", visible: :all
    end
  end

  test 'the page pulls in the application stylesheet and script bundle' do
    visit '/'

    # visible: :all -- rack-test has no layout engine, so it treats a <link>
    # with no text content as invisible. The asset tags are what matter here.
    #
    # Not asserting the csrf meta tag: config/environments/test.rb sets
    # allow_forgery_protection = false, so csrf_meta_tags renders nothing and
    # the assertion would only hold outside the test environment.
    assert_selector 'link[rel=stylesheet][href*="application"]', visible: :all
    assert_selector 'script[src*="application"]', visible: :all
  end

  test 'the search form offers the documented timeframes and result counts' do
    visit '/'

    options = page.all('select#timeframe option').map(&:text)
    assert_includes options, '10 minutes'
    assert_includes options, '1 day'
    assert_includes options, 'All records'

    counts = page.all('select#numresults option').map(&:text).map(&:to_i)
    assert_includes counts, 50
    assert_includes counts, 10_000
  end
end
