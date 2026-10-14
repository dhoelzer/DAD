require 'test_helper'

# The dashboard and host pages are .js.erb templates that call the statistics
# helpers directly. Those helpers used extract(), which SQLite rejects, so both
# pages raised on every dev/test run and nothing in the suite ever rendered them.
# These tests render them for real and assert the result is still parseable JS.
class DashboardRenderTest < ActionDispatch::IntegrationTest
  # The statistics helpers are instance methods of ApplicationHelper; integration
  # tests have no view `helper` proxy, so bind them onto a plain object.
  class ChartProbe
    include ApplicationHelper
  end

  def setup
    # The dashboard polls these .js endpoints with jQuery, i.e. as XHR. Without
    # the header Rails 4.2 rejects the request as cross-origin JS embedding.
    @headers = { 'X-Requested-With' => 'XMLHttpRequest' }

    @right = Right.create!(name: 'Viewer', description: 'read')
    @role = Role.create!(name: 'Viewer', description: 'read')
    @role.rights << @right
    @user = User.create!(username: "dash-#{SecureRandom.hex(6)}", attempts: 0)
    @user.store_password('hunter2')
    @user.save
    @user.roles << @role
    token = SecureRandom.hex(16)
    Session.create!(user: @user, expiry: Time.now + 1.hour, session_hash: token)
    cookies[:sessionID] = token

    # Event.recent_events sizes itself from the shared user_id 0 Preference row.
    # Nothing seeds that row, so create it here as a real deployment has it.
    Preference.create!(user_id: 0, liveEventsDisplayed: 10)
  end

  # Fixtures are dated 2014/2015, well outside every window the charts query, so
  # the helpers would return empty sets and prove little. Seed rows inside them.
  def seed_recent_data
    system = System.create!(name: 'dash-host', address: '10.0.0.9')
    service = Service.create!(name: 'dash-svc', description: 'Dash service')
    [[3, 10.0], [4, 20.0], [2, 5.0]].each do |hours_ago, stat|
      Statistic.create!(type_id: 0, stat: stat,
                         timestamp: hours_ago.hours.ago,
                         system_id: system.id, service_id: service.id)
      Statistic.create!(type_id: 1, stat: stat * 60,
                         timestamp: hours_ago.hours.ago,
                         system_id: system.id, service_id: service.id)
    end
    3.times do |i|
      Event.create!(system_id: system.id, service_id: service.id,
                    generated: (i + 1).hours.ago, stored: Time.now,
                    hunks: "dash event #{i}")
    end
    [system, service]
  end

  def test_dashboard_js_renders
    seed_recent_data
    get 'https://www.example.com/events.js', nil, @headers
    assert_response :success
    body = response.body

    # The helpers emit JS literals; a stray NaN/nil here means a query returned
    # nothing usable rather than raising.
    refute_match(/NaN/, body, "stats must not be NaN: #{body[0, 200]}")
    refute_match(/nil/, body, "stats must not contain nil: #{body[0, 200]}")
    assert_match(/var stats = \[\d+\.\d+, \d+\.\d+, \d+\.\d+\];/, body,
                 "hourly_stats must emit three numbers")
    assert_match(/draw_longitudinal\("logging_rate"/, body)
    assert_match(/draw_longitudinal\("insert_rate"/, body)
    assert_valid_javascript body
  end

  def test_host_page_js_renders
    system, = seed_recent_data
    get "https://www.example.com/systems/#{system.id}.js", nil, @headers
    assert_response :success
    body = response.body
    refute_match(/NaN/, body, "stats must not be NaN: #{body[0, 200]}")
    assert_match(/var stats = \[\d+\.\d+, \d+\.\d+, \d+\.\d+\];/, body)
    assert_match(/draw_longitudinal\("dash-host_graph"/, body)
    assert_valid_javascript body
  end

  # The chart helpers feed Highcharts [["label", n], ...]; assert the shape the
  # drawing code expects rather than just "it rendered".
  def test_hourly_series_labels_are_chart_formatted
    seed_recent_data
    chart_probe.events_per_hour(7.days.ago).each do |label, count|
      assert_match(%r{\A\d{1,2}/\d{1,2}/\d{4} \d{1,2}:00:00\z}, label,
                   "label must be M/D/YYYY H:00:00")
      assert_kind_of Integer, count
    end
    refute_empty chart_probe.events_per_hour(7.days.ago)
  end

  def test_bucket_labels_match_the_hour_they_come_from
    # A bucket is "YYYY-MM-DD HH"; the label must be the same hour, unpadded.
    assert_equal '10/13/2026 9:00:00', ApplicationHelper.chart_label('2026-10-13 09')
    assert_equal '1/5/2026 0:00:00', ApplicationHelper.chart_label('2026-01-05 00')
  end

  def test_approximate_count_falls_back_off_postgres
    # pg_stat_user_tables does not exist on sqlite; the dashboard calls this, so a
    # raise here would 500 the page rather than just mis-report.
    assert_kind_of Integer, Event.approximate_count
  end

  private

  def node_available?
    return @node_available unless @node_available.nil?
    @node_available = begin
      IO.popen(['node', '--version'], err: %i[child out], &:read)
      $?.success?
    rescue Errno::ENOENT
      false
    end
  end

  def chart_probe
    @chart_probe ||= ChartProbe.new
  end

  # The templates emit JavaScript, so "it rendered" is not enough -- a broken
  # literal parses as a syntax error only when the browser loads it. Hand the
  # body to node to prove it is valid JS. Runners without node still get the
  # render assertions above; only the parse check is skipped.
  def assert_valid_javascript(body)
    return unless node_available?
    path = Rails.root.join('tmp', 'dashboard_render.js').to_s
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    out = IO.popen(['node', '--check', path], err: %i[child out], &:read)
    # $? is only set once popen has reaped the child, i.e. after the block.
    assert $?.success?, "rendered JS did not parse: #{out}\n#{body[0, 300]}" 
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
