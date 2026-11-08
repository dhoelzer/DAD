require 'test_helper'

# The dashboard search form, exercised with the exact parameter shape a browser
# submits. Every other search test drives Event.search directly, so none of them
# ever saw the form's own parameter handling -- which is where the bug lived.
class SearchFormTest < ActionDispatch::IntegrationTest
  # datetime_select renders the form pre-filled to the current time, so an
  # absolute range built from those defaults is empty.
  NOW = Time.now

  def setup
    @headers = { 'X-Requested-With' => 'XMLHttpRequest' }

    @right = Right.create!(name: 'Viewer', description: 'read')
    @role = Role.create!(name: "viewer-#{SecureRandom.hex(6)}", description: 'read')
    @role.rights << @right
    @user = User.create!(username: "sf-#{SecureRandom.hex(6)}", attempts: 0)
    @user.store_password('hunter2')
    @user.roles << @role
    token = SecureRandom.hex(16)
    Session.create!(user: @user, expiry: Time.now + 1.hour, session_hash: token)
    cookies[:sessionID] = token

    # The ingestor's word/system/service caches and System/Service's
    # @@cached_stuff are process-global. Fixtures are rolled back between tests
    # but the caches are not, so without these resets the staged rows point at
    # word and system ids from a previous test's transaction.
    EventIngestor.resetCaches
    System.class_variable_set(:@@cached_stuff, Hash.new)
    Service.class_variable_set(:@@cached_stuff, Hash.new)
    EventIngestor.storeEvent('1.1.1.1 Jun 1 00:00:00 host svc[1]: needleword appears here')
    # A second event stamped now, so the relative-window tests can tell a
    # zero-length range apart from the intended one.
    EventIngestor.storeEvent("1.1.1.1 #{NOW.strftime('%Y-%m-%dT%H:%M:%SZ')} host svc[1]: recentneedle appears here")
    EventIngestor.performPendingInserts
  end

  def match_count
    body = response.body
    m = body.match(/(\d+) events match/)
    assert m, "no '... events match' in the response:\n#{body[0, 500]}"
    m[1].to_i
  end

  # The relative-timeframe branch: no timesearch_enabled key at all.
  test 'a relative timeframe search returns matches' do
    get 'https://www.example.com/events/search',
        params: { search_terms: 'needleword', timeframe: '50000000', numresults: 100 },
        headers: @headers
    assert_response :success
    assert_equal 1, match_count
  end

  # This is what the form actually posts when the box is left unticked: Rails'
  # check_box always emits the paired hidden field, so timesearch_enabled is
  # present as {"enabled"=>"0"}. Testing the presence of the key rather than its
  # value made this take the absolute-date branch with an empty now->now window.
  test 'an unticked Timeframe Search checkbox still uses the relative timeframe' do
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          timeframe: '50000000',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '0' },
          'lefttime' => datetime_fields(:start, NOW),
          'righttime' => datetime_fields(:end, NOW),
        },
        headers: @headers
    assert_response :success
    assert_equal 1, match_count,
      'an unchecked checkbox must not switch to the absolute-date branch'
  end

  # Ticking the box must honour the absolute window the operator chose.
  test 'a ticked Timeframe Search checkbox uses the chosen absolute window' do
    window_start = NOW - 365 * 24 * 3600
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          timeframe: '600',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => datetime_fields(:start, window_start),
          'righttime' => datetime_fields(:end, NOW + 3600),
        },
        headers: @headers
    assert_response :success
    assert_equal 1, match_count
  end

  # A ticked box with a window that genuinely excludes the event returns nothing.
  test 'a ticked checkbox with a window that excludes the event returns no matches' do
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => datetime_fields(:start, NOW - 2 * 3600),
          'righttime' => datetime_fields(:end, NOW),
        },
        headers: @headers
    assert_response :success
    assert_equal 0, match_count
  end

  # The form's datetime_select defaults are now->now, which is an empty window.
  # Silently reporting 0 matches for a nonsensical range is how the original bug
  # hid; the request must not 500 and must say so.
  test 'a nonsensical absolute window is reported rather than crashing' do
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => datetime_fields(:start, NOW),
          'righttime' => datetime_fields(:end, NOW),
        },
        headers: @headers
    assert_response :success
    assert_equal 0, match_count
  end

  # parse_datetime_params returns nil on garbage fields; #search used to hand
  # that straight to Event.search, which raised inside searchSQL on a nil bound.
  test 'garbage datetime fields do not raise' do
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => { 'start(1i)' => 'not-a-year' },
          'righttime' => { 'end(1i)' => 'not-a-year' },
        },
        headers: @headers
    assert_response :success
    assert_equal 0, match_count
  end

  # The timeframe select is the only way to widen the window from the UI, so a
  # missing or blank value must not collapse to a zero-length range and report
  # "0 events match" for data that is sitting right there.
  test 'a missing timeframe falls back to a usable window' do
    get 'https://www.example.com/events/search',
        params: { search_terms: 'recentneedle', numresults: 100 },
        headers: @headers
    assert_response :success
    assert_equal 1, match_count,
      'a missing timeframe must not become a zero-length range'
  end

  test 'a zero timeframe falls back to a usable window' do
    get 'https://www.example.com/events/search',
        params: { search_terms: 'recentneedle', timeframe: '0', numresults: 100 },
        headers: @headers
    assert_response :success
    assert_equal 1, match_count
  end

  # The form read @timeframes while the controller sets @timeframe, so the
  # select snapped back to "10 minutes" after every search.
  test 'the chosen timeframe is retained in the rendered form' do
    get 'https://www.example.com/events/search',
        params: { search_terms: 'needleword', timeframe: '604800', numresults: 100 },
        headers: @headers
    assert_response :success
    assert_includes response.body, '<option selected="selected" value="604800">1 week</option>',
      'the timeframe select must keep the value the operator chose'
  end

  # An unreadable date range must be reported, not silently answered with a
  # different window.
  test 'an unreadable date range is reported to the operator' do
    get 'https://www.example.com/events/search',
        params: {
          search_terms: 'needleword',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => { 'start(1i)' => 'not-a-year' },
          'righttime' => { 'end(1i)' => 'not-a-year' },
        },
        headers: @headers
    assert_response :success
    assert_match(/could not be read from the form/, response.body)
  end

  # The dashboard submits this form remotely, so the note has to survive the
  # .js path too, which replaces #stats rather than re-rendering the page.
  test 'the note is carried on the remote js path' do
    get 'https://www.example.com/events/search.js',
        params: {
          search_terms: 'needleword',
          numresults: 100,
          'timesearch_enabled' => { 'enabled' => '1' },
          'lefttime' => { 'start(1i)' => 'not-a-year' },
          'righttime' => { 'end(1i)' => 'not-a-year' },
        },
        headers: @headers
    assert_response :success
    assert_match(/could not be read from the form/, response.body)
  end

  # A normal search must not carry a note.
  test 'a successful search carries no note' do
    get 'https://www.example.com/events/search',
        params: { search_terms: 'needleword', timeframe: '50000000', numresults: 100 },
        headers: @headers
    assert_response :success
    refute_match(/could not be read from the form/, response.body)
  end

  private

  def datetime_fields(label, time)
    {
      "#{label}(1i)" => time.year.to_s,
      "#{label}(2i)" => format('%02d', time.month),
      "#{label}(3i)" => format('%02d', time.day),
      "#{label}(4i)" => format('%02d', time.hour),
      "#{label}(5i)" => format('%02d', time.min),
      "#{label}(6i)" => format('%02d', time.sec),
    }
  end
end
