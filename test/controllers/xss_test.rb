require 'test_helper'

# Event text and System names originate from syslog, so they are attacker
# controlled. These render the real search response and assert a payload cannot
# break out of its JavaScript or URL context.
class XssTest < ActionDispatch::IntegrationTest
  PAYLOAD = 'a";alert(1);//'

  setup do
    # The dashboard and search screens request these .js responses with
    # remote:true; without the XHR header Rails 4.2 rejects them as
    # cross-origin JavaScript embedding.
    @headers = { 'X-Requested-With' => 'XMLHttpRequest' }

    right = Right.create!(name: "Viewer", description: "view")
    role = Role.create!(name: "Viewers#{Time.now.to_i}", description: "viewers")
    role.rights << right
    user = User.create!(username: "viewer#{Time.now.to_i}", attempts: 0)
    user.store_password("secretsauce")
    user.roles << role
    hash = SecureRandom.hex(16)
    Session.create!(user: user, expiry: Time.now + 1.hour, session_hash: hash)
    cookies[:sessionID] = hash

    @system = System.create!(address: "xss.example.com", name: "xss#{Time.now.to_i}")
    @service = Service.create!(name: "xsssvc#{Time.now.to_i}")
    @event = Event.create!(system: @system, service: @service,
                           generated: Time.now, stored: Time.now,
                           hunks: "hostz tokenz #{PAYLOAD}")
    index_for_search(@event, %w[hostz tokenz])
    Event.resetCaches
  end

  # Event.search matches through the events_words join table, which ingestion
  # populates; write the rows a real import would have created.
  def index_for_search(event, tokens)
    tokens.each do |t|
      word = Word.create!(text: t)
      ActiveRecord::Base.connection.execute(
        "insert into events_words (event_id, word_id, generated) " \
        "values (#{event.id}, #{word.id}, '#{event.generated.to_s(:db)}')")
    end
  end

  def search_js_with_token(token)
    e = Event.create!(system: @system, service: @service, generated: Time.now,
                      stored: Time.now, hunks: "tokenz #{token}")
    w = Word.create!(text: "tokenz")
    ActiveRecord::Base.connection.execute(
      "insert into events_words (event_id, word_id, generated) " \
      "values (#{e.id}, #{w.id}, '#{e.generated.to_s(:db)}')")
    Event.resetCaches
    search_js("tokenz")
  end

  def search_js(terms)
    get "https://www.example.com/events/search.js",
        params: { search_terms: terms, timeframe: "3600", numresults: 10 }, headers: @headers
    assert_response :success
    response.body
  end

  # Rails HTML-escapes <%= %> in a JS template, which neutralises a quote but
  # leaves a backslash alone; a query ending in "\" used to emit a script that
  # node rejects as a syntax error.
  test "backslash in the query cannot terminate the JS string literal" do
    body = search_js('\\')
    line = body.lines.grep(/search_terms/).first.to_s
    assert_match(/value = "\\\\";/, line, "backslash must be escaped: #{line}")
  end

  test "query is emitted as one escaped JS string, not broken out of one" do
    body = search_js(PAYLOAD)
    line = body.lines.grep(/search_terms/).first.to_s
    assert_includes line, '\\"', "quote must be backslash-escaped: #{line}"
    assert_match(/value = ".*";\s*\z/, line, "assignment must be well formed: #{line}")
  end

  # The old hand-built href interpolated the token straight into the query
  # string, so a token containing & or " could close the attribute or inject a
  # parameter. search_events_path percent-encodes instead.
  test "per-word search links URL-encode hostile tokens" do
    hostile = 'q"onmouseover=alert(1)x'
    body = search_js_with_token(hostile)
    hrefs = body.scan(/href=\\?"([^"\\]*search[^"\\]*)/).flatten
    refute_empty hrefs, "expected per-word search links"
    target = hrefs.find { |h| h.include?("onmouseover") }
    refute_nil target, "hostile token should still appear as a link: #{hrefs}"
    query = target.split("?", 2).last
    assert_includes query, "%22", "quote must be percent-encoded: #{target}"
    assert_includes query, "%3D", "equals must be percent-encoded: #{target}"
    refute_match(/[&"]onmouseover/, query, "token must not break the query: #{target}")
  end

  test "a token containing an ampersand cannot inject a query parameter" do
    body = search_js_with_token("r&s=1")
    hrefs = body.scan(/href=\\?"([^"\\]*search[^"\\]*)/).flatten
    target = hrefs.find { |h| h.include?("r%26s") }
    refute_nil target, "ampersand in the token must be encoded: #{hrefs}"
  end

  test "search results still render for a benign query" do
    body = search_js("tokenz")
    assert_includes body, "1 events match that search"
    assert_includes body, "tokenz"
  end
end
