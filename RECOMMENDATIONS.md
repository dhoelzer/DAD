# DAD — Code Review & Improvement Recommendations

Reviewed at commit `db5c6b4` (last commit: 2016-10-01). ~2,300 lines of app code
(18 controllers, 17 models), plus standalone ingestion scripts (`syslog.pl`,
`import_syslog.rb`, `scheduler.rb`) and a Vagrant/Apache-Passenger provisioning path.

DAD is a genuinely interesting design: a syslog collector writes rolling files, a Ruby
importer tokenises each line into a `words` dictionary and an `events_words` join table
(a hand-rolled inverted index), and the Rails UI searches that index. The ingestion
throughput work (batched raw INSERTs, word/system/service caches, adaptive batch size)
is real engineering. The problem is that everything *around* that core — security,
data integrity, operability, tests — is prototype-grade, and the framework underneath
(Rails 4, EOL since 2017) is now a liability for a tool whose whole job is ingesting
untrusted network data.

Recommendations are ordered by priority. Each is tagged **[security]**, **[correctness]**,
**[performance]**, **[maintainability]**, or **[operations]**.

---

## 0. Status update: item 1 (reproducible, patched build + CI) is done

Landed on branch `reproducible-build-and-ci` (base `db5c6b4`). The app now installs,
boots, and runs a green test suite from a clean checkout.

**Reproducibility**
- `Gemfile` pins `rails '~> 4.2.11'` (was `'> 4'`, which resolved Rails 8 against
  Rails-4-era code). Every other gem pinned to a compatible line.
- `Gemfile.lock` and `db/schema.rb` are now committed (both were gitignored);
  `.ruby-version` pins Ruby 2.7.8; `Gemfile.lock` pins Bundler 1.17.3.
- `Dockerfile.dev` (ruby:2.7.8, `bundle install --frozen`) and
  `.github/workflows/ci.yml` (install → migrate → `rake test` → `cucumber`, plus a
  bundle-audit + Brakeman job) reproduce the toolchain anywhere.

**Patches needed to make Rails 4.2 run on a supported-ish Ruby**
- `bigdecimal ~> 1.4.4`: Ruby 2.7 ships bigdecimal 2.x, which removed
  `BigDecimal.new`; ActiveSupport 4.2 calls it during boot.
- `turbolinks ~> 2.5`: the views use `data-no-turbolink`, which Turbolinks 5 renamed.
- `test/test_helper.rb` shims `ActionController::TestCase::TestResponse#recycle!`:
  Rails 4.2 re-runs `initialize` on a `MonitorMixin` object, which Ruby >= 2.5
  forbids (`ThreadError: already initialized`). Every controller test died on this.

**Test suite: red → green (was 77 errors / 0 assertions)**
- Deleted fixtures/tests for tables and actions that no longer exist (`positions`,
  `display_fields`, and 10 controller tests exercising removed CRUD actions).
- Added `test/controllers/authorization_test.rb`: anonymous users are redirected, a
  right-bearing role can read, and passwords are stored hashed. This is the only
  test that covers the app's real behaviour.
- `config/initializers`-level: `config.active_support.test_order = :random`.

**Product bugs found and fixed by the now-working tests**
- **[correctness] Search silently hid events.** `Event.search`/`search_period` used
  `LIKE 'term%'` and `having count(distinct(word_id)) = n_terms`. A term that is a
  prefix of another word on the same event (`test` also matches `testservice` and
  `this-is-a-test`) inflates the count, so the equality never held and the event
  vanished from results. Replaced with a per-term `max(case when ... )` sum, and
  terms are now `sanitize_sql_like`-escaped. This is the app's core feature.
- **[correctness] `Event`'s class-level caches leaked across transactions.**
  `@@cached_words`/`@@system_cache`/`@@service_cache`/`@@nextEventID` hold row IDs;
  DatabaseCleaner rolls the DB back but cannot reach them, so the next scenario
  referenced dangling IDs. Added `Event.resetCaches` + a cucumber `Before` hook.
- **[correctness] The async insert thread deadlocked SQLite under test** and its
  results were never joined, so nothing written by `storeEvent` was observable.
  Inserts now run inline in `Rails.env.test?` only.
- The two unfinished alert scenarios are tagged `@wip` (the repo's existing
  convention) so `--strict` does not fail CI on them.

**Still open, discovered while doing this**
- `config/initializers/secret_token.rb` has a real `secret_key_base` committed since
  `de2043a`. Treat it as compromised: move to an env var and rotate. (Not changed
  here — rotating it invalidates every existing session cookie.)
- `bundle-audit` reports ~60 open advisories, mostly unpatchable on the Rails 4.2 /
  rack 1.6 line (several Critical: CVE-2022-30123 rack, CVE-2022-32224
  activerecord, CVE-2020-8165 activesupport). The CI security job is therefore
  `continue-on-error: true`; flip it to blocking after the Rails upgrade (item 13).
- Brakeman: XSS in `app/views/systems/show.js.erb:9`, `alerts/_alerts.html.erb:13`,
  `events/_event_detail.html.erb:4`, plus the CSRF-token weakness in 4.2.11.3.

---

## 1. Do this first: the app is remotely exploitable

This is not theoretical. `syslog.pl` listens on UDP/514 for untrusted input, and the
UI is exposed over HTTP/HTTPS with a hand-rolled auth layer.

### 1.1 SQL injection in the search path **[security]**
`app/models/event.rb:104` and `:119` interpolate the raw user query straight into SQL:

```ruby
terms = search_string.downcase.split(/\s+/)
sql = "... words.text LIKE '#{terms.join("%' union select id from words where words.text LIKE '")}%') ..."
```

`params[:search_terms]` reaches this from `EventsController#search` with no escaping or
allow-listing. A query containing `'` breaks out of the literal. The same pattern appears
in `System#events_since`, `System#hourly_stats`, `System#events_per_hour`,
`System.reportingInLastDays`, and four helpers in `ApplicationHelper`
(`events_per_hour`, `inserts_per_second`, `hourly_stats`, `daily_insert_average`) — those
interpolate Ruby values, so they are lower risk today, but they are one refactor away
from being injectable and they duplicate the same query five times.

**Fix:** use `connection.exec_query(sql, [binds])` / `sanitize_sql_for_conditions`, or
express the search with ActiveRecord (`Word.where(text: terms)` + `joins`), and delete
`search2`/`iterativeSQLBuilder` (dead code, and its own comment says *"this is massively
bad in so many ways"*). Add a regression spec that feeds `a' OR 1=1 --` through
`Event.search`.

### 1.2 Two `eval` sinks = remote code execution as root **[security]**
- `scheduler.rb:9` — `eval(job.script)` where `script` is a DB column that any user with
  the `Taskmaster` right can set through `JobsController` (`job_params` permits `:script`).
  The seed data even admits it: *"Extremely powerful. Can be used to compromise the system."*
  `scheduler.rb` runs as root under `provision.sh`.
- `Event#parsed` (`event.rb:70`) — `eval @display_helper.display_script`, where
  `display_script` is user-supplied via `DisplaysController`, and it is executed while
  rendering every event row (`app/views/events/_event_detail.html.erb:6`).

**Fix:** remove the `eval` sinks. Options, cheapest first: (a) gate the `Taskmaster` and
`Detective` rights behind an explicit config flag and document the trust boundary;
(b) replace `Job.script` with a registry of named, parameterised job classes
(`Job.perform("prune_events", args)`); (c) replace `Display#display_script` with a
declarative format the app interprets — field selection/rename by position, regex
capture groups, a whitelist of formatting helpers. A display filter should not be a
Ruby program.

### 1.3 Password hashing is broken by construction **[security]**
`app/models/user.rb:9-20`:

```ruby
salt = Random.srand % 9999
hash = Digest::SHA256.hexdigest "#{salt}#{password}"
```

Three problems: `Random.srand` (not `SecureRandom`) seeds the global PRNG and returns the
previous seed, so the salt space is ~10k values and is predictable; unsalted iterated
SHA-256 is GPU-crackable; and `check_password` compares with `==`, which is not
constant-time.

**Fix:** `gem "bcrypt"` + `has_secure_password` (or `Argument`/`scrypt`), with a migration
that re-hashes on next successful login. `db/migrate/20151225004757_use_password_hashes.rb`
already shows the pattern for a one-way upgrade; reuse it.

### 1.4 Password hashes leak through the JSON API **[security]**
`app/views/users/index.json.jbuilder` and `show.json.jbuilder` do
`json.extract! user, :id, :username, :password, ...`. Any caller that can reach
`/users.json` gets every salted hash. `SessionsController` also exposes full CRUD over
the `sessions` table (`session_params` permits `:user_id, :expiry`), i.e. an attacker can
mint a session row directly.

**Fix:** drop `:password` from every jbuilder (and never `select *` on `users`); make
`SessionsController` read-only (or delete it — sessions are an implementation detail of
`gatekeeper`). Add a request spec asserting `/users.json` has no `password` key.

### 1.5 Secrets committed to the repository **[security]**
- `config/initializers/secret_token.rb` — hard-coded `secret_key_base`. This signs Rails
  cookies; with it public, signed/encrypted cookies can be forged.
- `config/database.yml` — production DB user/password (`rails`/`example`) in git.
- `gather_eventlogs.rb:1` — a real WMI command with a domain account and password
  (`auditor%Password1`) plus internal hostnames (`*.enclaveforensics.com`). This file is
  a pasted shell transcript, not code.
- `provision.sh:112` — default admin password `Password1`, and the seeded admin hash in
  `db/seeds.rb:10` is the same value.

**Fix:** move all of it to environment variables (`ENV["SECRET_KEY_BASE"]`,
`ENV["DATABASE_URL"]`) or an untracked `config/application.yml`; rotate every credential
that has ever been committed; delete `gather_eventlogs.rb` (or reduce it to a documented
example with placeholders); force a password change on first admin login. Note
`.gitignore` currently ignores `db/schema.rb` but *not* `config/database.yml`, so the
password is in history — scrub with `git filter-repo` if the repo is public, and treat
the history as compromised regardless.

### 1.6 Session handling **[security]**
`UsersController#generate_session_id` builds a 62-char-alphabet token from
`rand(10000) % field.count` — biased modulo reduction on `Kernel#rand`, and `rand` is not
a CSPRNG. Sessions are never rotated on login (the code does delete prior sessions, which
is good), the cookie is not `SameSite`, and `gatekeeper` re-issues the cookie on every
request. `cookies[:sessionID] = nil` on logoff does not reliably delete a cookie.

**Fix:** `SecureRandom.hex(32)`; `cookies[:sessionID] = { value: nil }` or
`cookies.delete(:sessionID)`; add `same_site: :lax`; consider just using Rails' built-in
`ActionDispatch::Session` (already configured in `config/initializers/session_store.rb`
and unused) instead of a parallel DB session store.

### 1.7 XSS in the event renderer **[security]**
`app/views/events/_event_detail.html.erb:9` builds a link href by interpolating raw event
text (attacker-controlled, since it comes from syslog) into a URL query string with no
escaping:

```erb
<%= link_to position, "/events/search?search_terms=#{(@previous_search.nil? ? ... )}&timeframe=#{@timeframe}" ... %>
```

`search.js.erb:20` does `document.getElementById('search_terms').value="<%= @previous_search %>"`
— raw string into a JS literal. `timestamp_helper` returns an HTML string that callers
`raw`, and `systems/show.js.erb:8` interpolates `@system.name` (auto-created from log
input) into a JS string.

**Fix:** use `link_to position, search_events_path(search_terms: ..., timeframe: ...)` —
path helpers URL-encode their arguments. In JS templates use
`<%= j @previous_search %>` and assign via a data attribute rather than a string literal.
Audit every `<%=raw` (12 sites) and keep `raw` only where the value is provably numeric
or generated by the app.

### 1.8 Authorization is copy-pasted and inconsistent **[security]**
Every controller redefines a *public* `authorized?` method as a `before_filter` callback.
Because it's public, it is also routable (`GET /users/authorized?` etc.), and
`UsersController` overrides it with a version that redirects to `logon_users_path` while
`SessionsController`'s second definition redirects to `/homes` — a path that does not
exist in `routes.rb`. `PreferencesController` has **no** override, so any logged-in user
can read and write any other user's preferences. Rights checks are also scattered through
actions (`SearchesController` repeats the same `has_right?("Detective")` block five times).

**Fix:** one `ApplicationController` filter that maps `params[:controller]` → required
right (a constant hash), plus `protect_from_forgery with: :exception` (already present —
keep it). Make the check `private`/`helper_method` so it can't be routed. Delete the
per-action `unless @current_user.has_right?(...)` blocks. If you'd rather not hand-roll
this at all, `Pundit` or `CanCanCan` gives you the same roles/rights model with the
enforcement in one place.

---

## 2. Correctness bugs that are silently corrupting data

### 2.1 The dashboard drops *every* event when there are no exclusions **[correctness]**
`Event.recent_events` (`event.rb:31-40`):

```ruby
exclusions = Exclusion.pluck(:pattern)
reg = Regexp.union(exclusions)          # => /(?!)/  when exclusions is empty
.reject { |event| event.match(reg) }    # matches everything -> all events rejected
```

`Regexp.union([])` returns `/(?!)/`, which matches at every position, so with an empty
`exclusions` table the "recent events" pane is always empty and the adaptive
`@@num_last_events` logic then inflates the fetch size by 10% on every request — an
unbounded growth loop that also writes to `preferences` on every page load.

**Fix:** `reg = exclusions.empty? ? nil : Regexp.union(exclusions)` and skip the reject
when `reg` is nil. Also compile it once per request, not per event.

### 2.2 Timestamp parsing has a hard-coded 2014–2019 window **[correctness]**
`event.rb:196` — `elsif split_text[3].to_i > 2014 && split_text[3].to_i < 2020`. Every
event with a modern (2020+) year in that field falls through to the legacy
`"#{txttimestamp} #{@@current_year} GMT"` branch, which assumes the syslog day-of-year
format and stamps it with the *current* year. Depending on the log format this either
drops the event (parse raises, `rescue` → `return`) or files it under the wrong date.
This is the single most likely reason DAD appears to "lose" events today.

**Fix:** parse against a real format list (RFC3164, RFC5424, ISO-8601) with explicit
`DateTime.strptime` patterns, and treat unparseable timestamps as "now" plus a counter,
never as a silent `return`. Keep the raw line so the parse can be re-run later.

### 2.3 `Math` core module is reopened **[correctness]**
`config/application.rb:6-27` defines `module Math` with `mean`/`variance`/
`standard_deviation`/`sum_values`. Ruby's built-in `::Math` is a module (not a class), so
this *reopens the core module* rather than shadowing it — `Math.sqrt`, `Math.sin`, etc.
now live in the same namespace as these helpers, and `Math.standard_deviation` calls
`Math.sqrt` on the result. Two consequences: any code in the app (or any gem) that
expects `Math` to be purely numeric is now sharing a namespace with app code, and
`Math.mean([])` returns `NaN`/`0.0` rather than raising, which is how empty-statistics
pages end up drawing Highcharts gauges with `NaN` axes.

**Fix:** move these to `StatisticsCalculator` (or a `Stats` module) under `lib/`, and
guard the empty-array case. This is a two-line rename with outsized payoff.

### 2.4 Ingestion is not crash-safe and can double-insert **[correctness]**
`Event.performPendingInserts` (`event.rb:267-301`) hand-manages `@@nextEventID`,
`@@pendingEventValues`, `@@events_words` and up to 5 background `Thread`s, each of which
grabs `ActiveRecord::Base.connection` — the same connection object Rails hands out per
thread, which is a documented source of cross-thread query interleaving. The two INSERTs
(`events_words` then `events`) are not in a transaction, so a crash between them leaves
orphaned index rows. `import_syslog.rb` renames the file *after* processing, so a crash
mid-file re-processes the whole file on restart and collides with the manually assigned
IDs. `@@nextEventID` is also initialised with `Event.all.count` (`event.rb:235`) — a full
table scan on a table the README says holds hundreds of millions of rows.

**Fix:** wrap each batch in `ActiveRecord::Base.transaction`; let Postgres assign ids from
a sequence (`INSERT ... RETURNING id`) instead of a Ruby counter; move staged files to a
`.processing` name *before* reading them so a restart can't double-process; replace the
ad-hoc thread pool with a single-threaded batch loop (the throughput win came from batch
size, not concurrency) or with Sidekiq. Replace `Event.all.count` with
`Event.maximum(:id)`.

### 2.5 `storeEvent` mangles data to avoid quoting bugs **[correctness]**
`event.rb:260` — `hunks.gsub!("'", %q("))` with the comment *"This is non-optimal"*. The
importer is deliberately corrupting stored log text (single quotes → double quotes)
because the INSERT is string-built. That is data loss in a forensic tool.

**Fix:** parameterised inserts (`exec_import` / `insert_all` with bind values) remove both
the mangling and the injection risk in one step. Rails 6+ has `insert_all`, which is
exactly this use case.

### 2.6 Smaller but real
- `User#has_right?` (`user.rb:36-41`) queries `Right` twice per call and returns `true`
  for Admin unconditionally — fine, but it's called from the navbar for every model on
  every request (N+1). Memoise `rights`.
- `Alert#criticality_name` (`alert.rb:14`) compares `self.criticality == "4"` (string)
  while every other branch compares integers, so criticality 4 renders as "Critical"
  instead of "Serious".
- `Preference.eventsDashboard` writes to the DB on every dashboard poll.
- `routes.rb:67` declares `resources :positions`, but there is no `Position` model,
  controller, or migration — and `test/fixtures/positions.yml` exists, so the test suite
  references a table that doesn't exist.
- `SessionsController#authorized?` is defined twice; the first definition is dead.
- `app/models/service.rb:3` — `has_many :servers, through: :events` (no `Server` model).
- `db/migrate/20150422005353_create_indices_on_events_words.rb` is an empty migration
  (both `add_index` lines commented out) — see §3.1.

---

## 3. Performance: the search path is the product, and it's unindexed

### 3.1 `events_words` has no indexes **[performance]**
The join table that *is* the search index has no index on `word_id` or `event_id` — the
migration that would have added them is commented out. Combined with
`LIKE '%term%'` over `words.text` (unindexable by a B-tree), every search is a full scan
of a table that grows at ~300 rows/second × every word in the line. This is why the README
says *"the event search rate is extremely low"*.

**Fix (highest-value change in the repo):**
```sql
CREATE INDEX CONCURRENTLY ON events_words (word_id, event_id);
CREATE INDEX CONCURRENTLY ON events_words (event_id);
CREATE INDEX CONCURRENTLY ON events (generated);
```
Then replace the `LIKE '%term%'` dictionary lookup with an exact match
(`words.text = ANY(ARRAY[...])`) against `words(text)` with a B-tree or `text_pattern_ops`
index — the importer already normalises tokens, so exact lookup is the right semantics
and it makes the "wildcard" hack in the last commit unnecessary.

### 3.2 Postgres-native full-text search is the better long-term shape **[performance]**
The `words`/`events_words` model is a hand-rolled inverted index that costs one join row
per token per event — for a 300-word/sec ingest rate that's the dominant write cost and
the dominant storage cost. Postgres `tsvector` + GIN gives you the same query power
(token AND, phrase, ranking) with one indexed column per event row, plus `ts_rank` and
`ts_headline` for free.

**Fix:** add `search_vector tsvector` to `events` with a trigger, backfill in batches, and
re-point `Event.search`. Keep `words`/`events_words` behind a feature flag for one release
so the two can be compared on real data. This is a bigger change than §3.1 — do §3.1 now,
§3.2 when you have a maintenance window.

### 3.3 Partitioning and retention **[performance] [operations]**
`approximate_count` queries `pg_stat_user_tables where relname like 'events_p%'` — it
expects partitioned tables (`events_p…`) that no migration creates. Meanwhile
`import_syslog.rb`'s `purge_logs` body is commented out, so nothing prunes `events`,
`events_words`, or `statistics` at all. `statistics` gets a row per import batch, forever.

**Fix:** declare declarative range partitioning on `events (generated)` (monthly), add a
`pg_partman`-style or cron-driven retention job, and re-enable `purge_logs`. Add an index
on `statistics (type_id, timestamp)` since every dashboard helper filters on both.

### 3.4 N+1s in the dashboard helpers **[performance]**
`ApplicationHelper.system_stats` / `service_stats` / `system_service_stats` call
`System.find(id)` / `Service.find(id)` once per group, and `System.with_events_within_hours`
calls `System.find` per row. These run on every dashboard refresh (`index.js.erb` polls).

**Fix:** `joins(:system).group(...).pluck("systems.name", "count(*)")` — one query each.

---

## 4. Framework and dependency health

### 4.1 Rails 4 is EOL and the Gemfile can't reproduce a build **[operations]**
`Gemfile` pins `gem 'rails', '> 4'` — an *unbounded* upper bound, so `bundle install`
today resolves to Rails 8 against Rails-4-era APIs (`before_filter`, `Rails 3-style
`attr_accessible`-era asset config, `Rails::Application.configure`) and fails. There is no
`Gemfile.lock` (it's gitignored), `sass-rails ~> 4.0.0` and `coffee-rails ~> 4.0.0` are
years dead, `therubyracer` doesn't build on modern systems, and `sdoc`/`mail`/`httparty`
are unpinned. `provision.sh` installs Debian Jessie packages from a 2015 apt keyserver
flow (`apt-key adv`) that no longer works.

**Fix, in order:**
1. Commit a `Gemfile.lock` (remove it from `.gitignore`) and pin `rails '~> 4.2.11'` —
   the last 4.2 patch, which fixes the known Rails 4 CVEs. This gets a reproducible,
   patched build *today* without touching app code.
2. Add GitHub Actions: `bundle install && bundle exec rake test && brakeman -A`. This is
   the cheapest way to keep the security findings above from regressing.
3. Then plan the upgrade: 4.2 → 5.2 → 6.1 → 7.x, one hop per PR. The mechanical blockers
   are `before_filter` → `before_action`, `Rails::Application.configure` →
   `Rails.application.configure`, the `rails/all` requires, and dropping
   `therubyracer`/`sass-rails 4` for `dartsass-sprockets` or moving CSS to plain SCSS.
4. Replace the CoffeeScript scaffolds (11 near-empty `.js.coffee` files) and the
   hand-maintained `highcharts-custom.js` blob with a small ES module bundle, or drop the
   asset pipeline for static assets served by the front-end web server.

### 4.2 `provision.sh` is not idempotent and misleads **[operations]**
`sudo cat << EOF1 > /etc/apache2/sites-enabled/dad.conf` — `sudo` applies to `cat`, not to
the shell redirection, so this only works because the script is already root; it will
silently do the wrong thing under `sudo -u`. `ln -s` for the ssl mods fails on re-run
(use `a2enmod ssl`). Background processes (`perl syslog.pl &`, `ruby import_syslog.rb &`)
die on VM reboot and have no restart, no logging rotation, and no health check.

**Fix:** ship `systemd` unit files (`dad-syslog.service`, `dad-importer.service`,
`dad-scheduler.service`) with `Restart=always`, and make `provision.sh` a thin wrapper
around them (or replace it with a container/compose setup). Use `a2enmod ssl` and
`install -m 0644 ... <<EOF`.

---

## 5. Maintainability

### 5.1 The `Event` model is 320 lines of class-variable global state **[maintainability]**
`@@cached_words`, `@@system_cache`, `@@service_cache`, `@@pendingEventValues`,
`@@events_words`, `@@nextEventID`, `@@insertThreads`, `@@cachelifetime`, `@@num_cached`
are process-global mutable state on an AR model, mixed with instance-level `@bulk_insert_size`
and `@cache_hits` (which are *class-level* in effect because they're set in class methods —
a subtle bug source). This state is invisible to the web process, untestable in isolation,
and the reason the importer can't be run in parallel.

**Fix:** extract an `EventIngestor` service object that owns the caches and the batch
buffer, instantiated once by `import_syslog.rb`, with `Event` left as a persistence model.
This makes the ingestion path unit-testable without a DB and is the prerequisite for any
parallelism.

### 5.2 Dead and duplicated code **[maintainability]**
- `Event.search2` + `iterativeSQLBuilder` are unreachable (nothing calls them) and carry
  ~20 lines of commented-out experiments. Delete.
- `Event.search` and `Event.search_period` are the same 12 lines with a different
  time bound. Merge into one method taking a range.
- The `authorized?` block is duplicated across 15 controllers (§1.8).
- `System#hourly_stats` and `System#events_per_hour` are the same query; four
  `ApplicationHelper` methods are the same statistics query with a different aggregate.
- `export_logs.rb`, `gather_eventlogs.rb` (a pasted transcript), and `syslog.pl`'s unused
  `$DEBUG`/`$Filename` globals.
- 11 empty-ish `*.js.coffee` scaffolds and 13 `*.css.scss` scaffolds from `scaffold :model`.

**Fix:** delete the unreachable paths outright (git keeps them). Extract the shared
statistics query into one helper with named scopes.

### 5.3 The test suite is red and misleading **[maintainability]**
`test/controllers/events_controller_test.rb` tests `new`/`create`/`edit`/`update`/`destroy`
— none of which exist on `EventsController` anymore. `test/fixtures/positions.yml`
references a nonexistent table. All 11 model tests are empty comment blocks. The Cucumber
features test `Word.create` directly rather than `Event.storeEvent`'s real path, and
`features/support/env.rb` calls `DatabaseCleaner.strategy = :transaction` while the
`database_cleaner` gem is commented out in the `Gemfile` — so cucumber raises
`"You need to add database_cleaner to your Gemfile"` on load. There is no CI config of any
kind (no `.github/`, `.travis.yml`, `Rubocop`, or `.rspec`).

**Fix:** delete the stale controller tests rather than trying to repair them, then write
the tests that actually protect the product:
1. `Event.storeEvent` → `performPendingInserts` round-trip (parse, cache, batch, insert).
2. Timestamp parsing table-driven tests across RFC3164 / RFC5424 / ISO-8601 / malformed.
3. `Event.search` against known fixtures, including an injection attempt.
4. Request specs for the auth matrix: unauthenticated → redirect; Viewer → can read,
   cannot write; `/users.json` has no `password`.
Run them in CI (§4.1).

### 5.4 `puts` as the only observability **[operations]**
`Event.search`/`search_period`/`approximate_count` `puts` the generated SQL on every call
(`event.rb:47,105,120,163`) — in production that goes to the Passenger log, unbounded, and
leaks query internals. `prune_words` `puts` cache stats. `import_syslog.rb` rescues
`Exception` (not `StandardError`), prints the offending line, flushes, and `exit`s — one
bad line kills the collector.

**Fix:** use `Rails.logger` with a log level, and `ActiveSupport::Notifications` around
search/insert so timings land in the log with structured fields. Rescue `StandardError`
per line, count failures into a `Statistic`, and keep going.

---

## 6. Suggested sequence

| # | Change | Effort | Payoff |
|---|--------|--------|--------|
| 1 | ✅ **Done** — `Gemfile.lock` committed, `rails ~> 4.2.11` pinned, CI + Brakeman + Dockerfile, suite green | hours | reproducible, patched build; catches everything below |
| 2 | Parameterise all SQL; delete `search2`/`iterativeSQLBuilder` | hours | closes the injection hole |
| 3 | Indexes on `events_words`, `events.generated`, `words.text` | minutes | the search fix the README has been asking for since 2015 |
| 4 | Remove `:password` from jbuilders; make `SessionsController` read-only | minutes | stops hash leakage |
| 5 | `has_secure_password`/bcrypt + migration; `SecureRandom` session ids | day | fixes authn primitives |
| 6 | Secrets → env vars; rotate committed credentials; scrub history | day | closes the committed-secrets blast radius |
| 7 | Fix `Regexp.union([])`, the 2014–2019 year window, and `module Math` | day | stops silent data loss/corruption |
| 8 | Single `authorized?` filter + rights map; fix `PreferencesController` | day | closes the authz gaps |
| 9 | Replace `eval` in `scheduler.rb` and `Display#display_script` | 2–3 days | removes the RCE sinks |
| 10 | Transactions + `insert_all` + staged-file rename in the importer | 2 days | crash-safe, no quote mangling |
| 11 | Retention/partitioning + re-enable `purge_logs` | 2 days | keeps the DB usable at 300 eps |
| 12 | Extract `EventIngestor`; write the real test suite | 1 week | makes the core changeable |
| 13 | Rails 5→7 upgrade, one hop per PR | ongoing | removes the EOL liability |

If you only do three things: **#2 (SQL injection), #3 (indexes), #7 (silent data loss)**.
Those are the ones that make the tool both safe and actually usable.

---

*This review was produced by an AI agent (OpenHands) on behalf of the user.*
