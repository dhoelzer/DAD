#!/usr/bin/env ruby
# Deterministic functional probe. Enumerates GET routes, authenticates the way
# the controller tests do (Session row + :sessionID cookie, Admin right), fetches
# each route as both HTML and .json, and records status/content-type/body digest.
#
# Its purpose is cross-version comparison during a Rails upgrade: run it on the
# pre-upgrade tree and the upgraded tree and diff the JSON. Everything it emits
# is deterministic for a given tree, so any diff is a real behaviour change.
# See the workflow notes at the bottom of this file.
#
# Usage:
#   bundle exec ruby script/probe.rb > probe-out.json
#   PROBE_DUMP_DIR=/tmp/dump bundle exec ruby script/probe.rb  # also write raw bodies
#   PROBE_APP_DIR=/path/to/other-checkout bundle exec ruby script/probe.rb
#
# Runs against the test database and WRITES to it (fixtures + probe auth rows).
# Use a scratch db/test.sqlite3, never a database you care about.
require 'digest'
require 'json'
require 'time'
require 'date'

APP = ENV['PROBE_APP_DIR'] || File.expand_path('..', __dir__)
Dir.chdir(APP)
ENV['RAILS_ENV'] = 'test'

# Freeze the clock before anything loads. Views render datetime_select with the
# current time, so an unfrozen clock makes the minute/hour option selections
# differ between runs and produces false-positive digest diffs.
FIXED_NOW = Time.utc(2020, 6, 15, 12, 30, 0)
module FrozenNow
  def now = FIXED_NOW
end
Time.singleton_class.prepend(FrozenNow)
Date.singleton_class.prepend(Module.new { def today = FIXED_NOW.to_date })

require File.join(APP, 'config', 'environment')
require 'action_dispatch'
require 'active_record'

out = {}
Rails.application.reload_routes! if Rails.application.respond_to?(:reload_routes!)
out[:routes] = Rails.application.routes.routes.map do |r|
  { name: r.name, verb: r.verb, path: r.path.spec.to_s.sub(/\(\.:format\)$/, '') }
end

ActiveRecord::Base.establish_connection(:test)

# Deterministic auth: fixed ids/tokens so the cookie and rendered pages are
# byte-stable across runs.
def ensure_auth!
  admin_right = Right.find_by(id: 900_000) || Right.new(id: 900_000)
  admin_right.name = 'Admin'
  admin_right.description = 'admin'
  admin_right.save!

  role = Role.find_by(id: 900_003) || Role.new(id: 900_003)
  role.name = 'ProbeAdmins'
  role.description = 'probe'
  role.save!
  role.rights = [admin_right]

  u = User.find_by(id: 900_001) || User.new(id: 900_001)
  u.username = 'probeuser'
  u.first = 'Probe'
  u.last = 'User'
  u.attempts = 0
  u.store_password('ProbePassw0rd!') if u.password.blank?
  u.save!
  u.roles = [role]

  s = Session.find_by(id: 900_002) || Session.new(id: 900_002)
  s.user_id = u.id
  s.expiry = Time.now + 10_000_000
  s.session_hash = 'probe_fixed_session_token_0000000000'
  s.save!
  s.session_hash
end
# Seed the fixture rows the pages need. Without this the probe's route filling
# depends on whatever a previous test run left in the DB, so two worktrees
# produce different sample sets. Fixtures are loaded with explicit ids so the
# data is byte-identical everywhere.
def seed_fixtures!
  dir = File.join(APP, 'test', 'fixtures')
  order = %w[systems services words users roles rights alerts comments displays
             events jobs searches statistics preferences exclusions hunks]
  # Wipe first so a leftover row from an earlier run cannot collide with a
  # fixture id or change which id first_id() picks.
  order.each do |name|
    next unless File.exist?(File.join(dir, "#{name}.yml"))
    klass = name.classify.constantize
    klass.connection.execute("DELETE FROM #{klass.table_name}")
  rescue ActiveRecord::NoSuchTable, NameError
  end
  Event.connection.execute('DELETE FROM events_words') rescue nil
  order.each do |name|
    next unless File.exist?(File.join(dir, "#{name}.yml"))
    ActiveRecord::FixtureSet.create_fixtures(dir, [name])
  end
end
# fixtures wipe users/roles/rights, so this must run before ensure_auth!.
seed_fixtures!
TOKEN = ensure_auth!

def first_id(model)
  k = model.to_s.classify.constantize
  r = k.order(k.primary_key).first
  r && r.id
rescue NameError
  nil
end

# gatekeeper rewrites session.expiry to Time.now + 1.hour on every request, so
# any now-derived timestamp in a body is inherently unstable. Normalise those
# (window: 400 days; fixture timestamps are 2014-2015, ~4300 days back).
# (and object addresses in error text) out of the digest; fixture/data
# timestamps are fixed and fall outside the window, so they still compare.
NOW = Time.now
TS_RE = /\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?/
# Sprockets fingerprints the bundle into every page's <script>/<link> tag, so a
# change anywhere in the asset pipeline would otherwise show up as a diff on
# every HTML page. Asset output is verified separately (byte-compare the built
# bundle, plus the CI jQuery-3 assertion), so the probe collapses the digest and
# measures page rendering only.
ASSET_RE = /application-[0-9a-f]{64}\.(js|css)/
def normalize(body)
  body.gsub(TS_RE) do |m|
    begin
      t = Time.parse(m.sub(/\.\d+/, '').sub(/[+-]\d{2}:?\d{2}\z/, ''))
      (t - NOW).abs < 400 * 86_400 ? 'TS_NOW' : m
    rescue ArgumentError
      m
    end
  end.gsub(/0x[0-9a-f]+/, '0xADDR').gsub(/\$2[aby]\$\d{2}\$[.\/0-9A-Za-z]{53}/, 'BCRYPT').gsub(ASSET_RE, 'application-DIGEST.\1')
end

samples = []
out[:routes].each do |r|
  next unless r[:verb] == 'GET'
  path = r[:path]
  next if path =~ /\A\/rails\// || path.include?('*')
  filled = path.gsub(/:([a-z_]+)_id\b/) { first_id($1) || '1' }
  # Plain :id takes the id of the resource the path is nested under, so
  # /users/:id renders a real user. Falling back to a literal 1 made every
  # member route 404 -- which meant show/edit/roles were silently never
  # rendered, and a defect confined to those views (the bcrypt hash the users
  # views leaked) produced no diff at all.
  filled = filled.gsub(/:id\b/) { first_id(path.split('/').reject(&:empty?).first) || '1' }
  next if filled =~ /:/
  next if filled =~ %r{/(logon|logoff|do_logon)$}
  ['', '.json'].each do |fmt|
    url = fmt.empty? ? filled : filled + fmt
    next if url == '/.json'
    # The app's #ssl before_action redirects http -> https outside development,
    # so request over https or every response is a 302 and nothing renders.
    absolute = 'https://probe.test' + url
    begin
      sess = ActionDispatch::Integration::Session.new(Rails.application)
      sess.get(absolute, headers: { 'Cookie' => "sessionID=#{TOKEN}" })
      raw = sess.response.body.to_s
      if ENV['PROBE_DUMP_DIR']
        require 'fileutils'
        FileUtils.mkdir_p(ENV['PROBE_DUMP_DIR'])
        File.write(File.join(ENV['PROBE_DUMP_DIR'], url.gsub(/[^a-z0-9]/i,'_') + '.' + (fmt.empty? ? 'html' : 'json')), raw)
      end
      body = normalize(raw)
      samples << { path: url, fmt: fmt.empty? ? 'html' : 'json',
                   status: sess.response.status,
                   ctype: sess.response.headers['Content-Type'].to_s,
                   bytes: body.bytesize,
                   digest: Digest::SHA256.hexdigest(body)[0, 16],
                   loc: sess.response.headers['Location'].to_s }
    rescue => e
      samples << { path: url, fmt: fmt.empty? ? 'html' : 'json',
                   error: normalize("#{e.class}: #{e.message[0, 140]}") }
    end
  end
end
out[:get_samples] = samples.sort_by { |s| [s[:path], s[:fmt]] }

conn = ActiveRecord::Base.connection
out[:ddl] = conn.select_rows('SELECT type, name, sql FROM sqlite_master ORDER BY type, name')
                .map { |t, n, s| "#{t}|#{n}|#{s}" }

p = {}
begin; p[:event_count] = Event.count; rescue => e; p[:event_count] = e.message; end
begin; p[:approx_count] = Event.approximate_count; rescue => e; p[:approx_count] = "#{e.class}: #{e.message[0, 120]}"; end
begin
  p[:search_period] = Event.search_period('MyString', Time.utc(2000, 1, 1), Time.utc(2100, 1, 1), 0, 10).map(&:id).inspect
rescue => e; p[:search_period] = "#{e.class}: #{e.message[0, 140]}"; end
begin
  p[:search] = Event.search('MyString', Time.utc(2000, 1, 1), 0, 10).map(&:id).inspect
rescue => e; p[:search] = "#{e.class}: #{e.message[0, 140]}"; end
begin
  sql, binds = Event.searchSQL(Time.utc(2000, 1, 1), Time.utc(2100, 1, 1), %w[MyString two])
  p[:searchSQL] = [sql, binds]
rescue => e; p[:searchSQL] = "#{e.class}: #{e.message[0, 140]}"; end
begin
  p[:word_lookup] = Event.send(:word_lookup, 'MyString')
rescue => e; p[:word_lookup] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:system_with_events] = System.with_events_within_hours(24).map(&:id).inspect; rescue => e; p[:system_with_events] = e.message; end
sid = System.order(:id).first&.id
begin; p[:system_events_since] = System.find(sid).events_since(Time.utc(2000, 1, 1)); rescue => e; p[:system_events_since] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:hourly_counts] = System.hourly_counts(sid, Time.utc(2000, 1, 1)).to_a.inspect; rescue => e; p[:hourly_counts] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:hourly_buckets] = System.hourly_buckets(sid, Time.utc(2000, 1, 1)).inspect; rescue => e; p[:hourly_buckets] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:reportingInLastDays] = System.reportingInLastDays(30).to_a.inspect; rescue => e; p[:reportingInLastDays] = "#{e.class}: #{e.message[0, 140]}"; end
# find_or_add writes; run it inside a rolled-back transaction so the probe does
# not change the DB state that later runs' page renders depend on.
begin
  p[:find_or_add] = ActiveRecord::Base.transaction do
    r = System.find_or_add('probe-system').id
    raise ActiveRecord::Rollback
    r
  end
rescue => e; p[:find_or_add] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:number_of_cached_items] = System.number_of_cached_items; rescue => e; p[:number_of_cached_items] = e.message; end
begin; p[:diskUtilization] = Event.diskUtilization; rescue => e; p[:diskUtilization] = "#{e.class}: #{e.message[0, 140]}"; end
begin; p[:event_pruning_count] = Event.event_pruning_count; rescue => e; p[:event_pruning_count] = e.message; end
begin; p[:to_fs_db] = Time.utc(2020, 1, 2, 3, 4, 5).to_fs(:db); rescue => e; p[:to_fs_db] = "#{e.class}: #{e.message[0, 120]}"; end
begin; p[:to_s_db] = Time.utc(2020, 1, 2, 3, 4, 5).to_s(:db); rescue => e; p[:to_s_db] = "#{e.class}: #{e.message[0, 120]}"; end
begin; p[:to_json] = { a: 1, t: Time.utc(2020, 1, 2) }.to_json; rescue => e; p[:to_json] = "#{e.class}: #{e.message[0, 120]}"; end
begin
  u = User.find(900_001)
  p[:password_roundtrip] = [u.check_password('ProbePassw0rd!'), u.check_password('wrong'), u.legacy_hash?]
  p[:has_admin_right] = u.has_right?('Admin')
rescue => e; p[:password_roundtrip] = "#{e.class}: #{e.message[0, 120]}"; end
out[:probes] = JSON.load(JSON.generate(p).gsub(/0x[0-9a-f]+/,'0xADDR'))

out[:rails_version] = Rails.version
out[:ruby_version] = RUBY_VERSION
puts JSON.pretty_generate(out)

# ---------------------------------------------------------------------------
# Cross-version workflow (how this was used for 7.1 -> 7.2 -> 8.0 -> 8.1)
# ---------------------------------------------------------------------------
#
#   git worktree add /tmp/base <pre-upgrade-sha>
#   (cd /tmp/base && bundle lock && BUNDLE_WITHOUT=production bundle install)
#
#   # run each tree with ITS OWN bundle, but always the SAME script:
#   PROBE_APP_DIR=/tmp/base bundle exec ruby script/probe.rb > base.json
#   PROBE_APP_DIR=$PWD      bundle exec ruby script/probe.rb > head.json
#
#   # compare: routes, per-route status/content-type/digest, DDL, model probes
#   diff <(jq -S . base.json) <(jq -S . head.json)
#
# What each section catches:
#   routes    -- a route removed, renamed or re-ordered by a railtie change
#   samples   -- a page that changed status, content type, or rendered bytes
#   ddl       -- schema drift between what migrations build and what the
#                previous version built (column types, index names)
#   probes    -- model-level behaviour the HTTP layer does not exercise:
#                Event.search/searchSQL bind order, System aggregate queries,
#                bcrypt round-trip, Time#to_fs(:db), to_json encoding
#
# Normalisation the probe applies so diffs are not noise: the clock is frozen
# before Rails loads (datetime_select otherwise varies by minute); timestamps
# within 400 days of "now" collapse to TS_NOW because gatekeeper rewrites
# session.expiry every request; object ids -> 0xADDR; bcrypt hashes -> BCRYPT
# (the salt differs per run); sprockets asset digests -> application-DIGEST.
#
# Known-good diffs, for reference: the Rails 8.1 step changed only the
# utf8_enforcer_tag attribute order in form HTML. If you see that diff, it is
# expected; a diff in any other page is not.
