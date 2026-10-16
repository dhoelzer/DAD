# DAD — agent context

Log aggregation/monitoring app: `syslog.pl` (UDP/514 collector) → `Logs/LogStaging` →
`Logs/LogsToProcess` → `import_syslog.rb` → Postgres (`events` + `words` + `events_words`
inverted index) → Rails UI (dashboards, search, alerts, jobs, custom RBAC).
`scheduler.rb` polls the `jobs` table and `eval`s each `script`.

## Build / test (as of the reproducible-build branch)
- Toolchain: Ruby 3.3.8 + Bundler 2.6.7 (pinned in `.ruby-version` / `Gemfile.lock`
  "BUNDLED WITH"). Rails is 8.1.4 (`~> 8.1.0`), tagged `rails-8.1.4`; the path was
  7.1.6 -> 7.2.3.2 -> 8.0.5.1 -> 8.1.4, one commit per minor step. Ruby jumped at
  the 7.1 step rather than at 7.2 because nokogiri and sqlite3 had already dropped
  2.7. 3.3.8 sits above the 7.2 (3.1) and 8.1 (3.2) floors, so no step after 7.1
  needed any Ruby work.
- `minitest ~> 5.25` is still load-bearing and easy to "clean up" by mistake:
  minitest 6 narrowed `Minitest::Test.run` to `(reporter, options)` and railties'
  TestUnit runner still calls it with 3 args, so every test dies with "wrong
  number of arguments (given 3, expected 1..2)". railties 8.0 dropped minitest
  from its runtime dependencies entirely, so nothing else holds the 5.x line.
  `json` moved `~> 2.7` -> `~> 3.1` at the 8.1 step: ActiveSupport <= 8.0 called
  `JSON.generate(jsonified, quirks_mode: true, max_nesting: false)` and json 3.x
  removed that keyword, so the 2.7 pin was load-bearing through 7.1/7.2/8.0 (all
  34 jbuilder views die without it); 8.1.4 calls plain `JSON.generate`. The floor
  is kept explicit so a future json 4 cannot arrive transitively. `sqlite3` went
  `~> 1.7, < 2` -> `~> 2.1` at 8.0, whose adapter *requires* >= 2.1.
- `Gemfile.lock` and `db/schema.rb` are now tracked on purpose — do not re-add them
  to `.gitignore`.
- Run tests: `bundle install --frozen` (set `BUNDLE_WITHOUT=production` to skip `pg`),
  `bundle exec rake db:migrate RAILS_ENV=test`, `bundle exec rake test`,
  `bundle exec cucumber`. Use the cucumber **binary**, not `rake cucumber:ok` — the
  rake task runs cucumber in-process and minitest's autorun then dies on `--profile`.
- CI: `.github/workflows/ci.yml` (test + a `security` job with three **blocking**
  gates: `bundle-audit`, `brakeman`, and `gitleaks` over the working tree via
  `.gitleaks.toml`). `Dockerfile.dev` mirrors the same pinned toolchain.
  `gitleaks` is pinned by version *and* sha256 in the workflow; if you bump it,
  update `GITLEAKS_SUM` from the release's own `_checksums.txt`.
- Rails upgrades here keep breaking on **renamed-but-not-raising config keys**:
  `Rails::Railtie::Configuration#method_missing` swallows unknown `config.*` writes
  instead of erroring, so a renamed setting silently stops applying (4.2->5.2 hit
  `serve_static_files`->`public_file_server.*` and the Sprockets-2-only
  `assets.enabled`). On each step, diff production behaviour (asset tag URLs,
  middleware stack, `db/schema.rb` DDL) against the previous version, not just
  the test suite.
- Upgrades also break **only in paths the suite barely touches**. 5.2->6.1 hit:
  jbuilder's template handler arity (every `.json.jbuilder` view, fails at render
  time), `create_join_table` raising on a column the block re-declares (only on a
  from-scratch `db:migrate`, which is what CI runs), and Active Storage demanding
  `config/storage.yml` once `eager_load = true` loads `Blob`. Probe JSON endpoints
  and boot production explicitly; `rake test` alone passes through all three.
- `require 'logger'` lives in `config/boot.rb`, not `application.rb`: concurrent-ruby
  >= 1.3.5 stopped requiring it, Rails 6.1 needs it before activesupport loads, and
  `bin/rails` reaches activesupport before `application.rb` does.
- `rspec-rails` is required even though there is no `spec/` directory: cucumber-rails
  only mixes `RSpec::Matchers` into `Cucumber::Rails::World` when
  `rspec/rails/matchers` is loadable, and the cucumber steps call `expect`. Dropping
  it fails all 4 scenarios with `undefined method 'expect'`.
- `cucumber-rails` had to move `~> 2.6` -> `~> 3.1` for Rails 8: 2.6.x caps
  `railties < 8`, which is what blocked the 8.0/8.1 steps. 3.1.x is the oldest line
  accepting railties 8 and keeps the `features/support/env.rb` API unchanged;
  `database_cleaner 1.99` still satisfies it. `rspec-rails 6.1.5` needed no change.
- `config/initializers/assets_precompile.rb` exists because Rails 7.1's Active
  Storage / Action Cable / Action Text engines append ES6 bundles to
  `config.assets.precompile`, which uglifier 2.7 cannot parse (`assets:precompile`
  dies on `FileChecksum`). The app uses none of those features. Engine initializers
  run *after* `config/initializers`, so the subtraction must sit in
  `after_initialize`. Verified: the built `application.js`/`application.css` digests
  are byte-identical to the 6.1 build.
- `secret_key_base` no longer comes from `config/secrets.yml` for dev/test: Rails
  7.1 deprecates `Rails.application.secrets` (removed in 7.2). The committed dev/test
  keys now live in `config/environments/{development,test}.rb` as
  `config.secret_key_base = ENV["SECRET_KEY_BASE"] || '<key>'`; `config/secrets.yml`
  keeps only the production `ENV["SECRET_KEY_BASE"]` pass-through, and
  `config/initializers/require_secrets.rb` reads `ENV` directly. Production still
  fails closed when `SECRET_KEY_BASE` is unset.
- **`secret_key_base` does not sign the login cookie.** Login state is
  `cookies[:sessionID]`, a `SecureRandom.hex(32)` token stored in the `sessions`
  table and written as a *plain* cookie value; `gatekeeper` resolves it with
  `Session.find_by(session_hash: ...)`. Nothing in the app uses
  `cookies.signed`/`cookies.encrypted`/`MessageVerifier`/`MessageEncryptor`. The
  Rails `cookie_store` session (`_Events_session`) *is* signed by
  `secret_key_base`, but it carries only the CSRF token and flash — no code
  reads `session[]` for auth. Consequences worth remembering: leaking
  `secret_key_base` defeats CSRF protection but does **not** impersonate anyone,
  and rotating it logs nobody out (sessions are DB rows). An earlier revision of
  `RECOMMENDATIONS.md` §1.1 got this backwards and claimed account takeover.
  Rotate with `bin/rotate_secret_key_base`; `provision.sh` only generates the
  key on first run, so it is not the rotation path.
- `ActiveSupport`'s `to_time` behaviour changed across these steps and the app
  never calls `config.load_defaults`, so *no* `load_defaults`-gated default is ever
  applied here — every behaviour change must be opted into by hand. Sequence: 7.2
  deprecated leaving `to_time_preserves_timezone` unset; 8.0 deprecated the boolean
  form in favour of `config.active_support.to_time_preserves_timezone = :zone`;
  8.1 removed the switch and hardcoded `:zone`. Setting `:zone` at 8.0 made the 8.1
  step provably neutral. Inert for this app (no `to_time` in app/ or lib/, and both
  `Time.zone` and the system zone are UTC).
- 8.1 renamed `DatabaseConfigurations#pool` -> `#max_connections` (old name
  deprecated, gone in 8.2). `test/models/event_ingest_flush_test.rb` read the old
  accessor and now uses the new one; `database.yml`'s `pool:` key still feeds it.
- Rails 8.1 rebuilt `utf8_enforcer_tag` from a raw string literal into a `tag()`
  call, so every form's utf8 enforcer input now renders `type="hidden"` *before*
  `name="utf8"`. Attribute order only — same attributes, value and encoding. Any
  byte-exact HTML comparison across the 8.0/8.1 boundary trips on it; normalise.
- Comparing behaviour across versions: use `git worktree add` on the previous
  upgrade commit and run a probe script against both. Freezing the clock is
  mandatory (`datetime_select` embeds `Date.today`/`Time.now` in option values),
  fixtures must be loaded before the probe's auth setup (Rails 7.1+ hashes fixture
  labels, so ids are stable and identical in both trees), and bcrypt hashes, object
  addresses and now-derived timestamps must be normalised out of the digest. With
  that in place the 7.1->7.2 and 8.0->8.1 diffs were empty apart from the utf8 tag.
- When checking for deprecations, unset `SECRET_KEY_BASE` (and other app env vars)
  first. A leaked `SECRET_KEY_BASE` makes Rails take the ENV branch and hides
  config-path problems — that is exactly how the `secrets` deprecation stayed
  invisible locally while CI showed it on every boot.
- Production serves assets through `config.assets.compile = true` (line 30 of
  `production.rb` is commented out) with `digest = false`, so the layout emits the
  undigested `/assets/application.js` and sprockets compiles it on demand. Verified
  200 on a real production boot. `provision.sh` never runs `assets:precompile`.

## Facts worth remembering
- Last upstream commit: 2016-10-01. Before the reproducible-build branch: `rails '> 4'`
  unpinned, no `Gemfile.lock`, no `db/schema.rb`, no CI.
- `bundle-audit` at 8.1 reports 4 advisories, all unchanged by the framework bump:
  `httparty 0.18.1` (CVE-2024-22049, CVE-2025-68696 — and httparty is referenced
  nowhere in app/, lib/ or test/, so it is a candidate for removal) and
  `jquery-rails 4.3.5` (CVE-2020-11023, CVE-2020-23064, fixed in jquery-rails 4.4.0).
- `/users` (HTML) renders the bcrypt `password_hash` column into the table body.
  Confirmed while diffing probe output: the only per-run variation in that page is
  the hash's random salt. Listing users should not emit hashes.
- App class is `Events::Application`; DB is Postgres in production, SQLite in dev/test,
  but the code uses PG-only SQL (`pg_stat_user_tables`, `extract()`) → dev/test diverge.
- Auth is hand-rolled: `users`/`roles`/`rights` + `sessions` table + `cookies[:sessionID]`.
  Each controller overrides a public `authorized?` method (also routable as an action).
- Ingestion lives in `EventIngestor` (`app/models/event_ingestor.rb`), split out
  of `Event` (§4.1). `Event` is the model and the read side only: associations,
  search, the dashboard feed. `EventIngestor` holds the write-side state in
  class-level instance variables (`@pendingEventValues`, `@nextEventID`,
  word/system/service caches, checkpoint bookkeeping) and builds raw multi-row
  INSERTs. It is process-global and assumes one long-running importer.
  `resetCaches` is the single place that state is defined and runs once at load.
  Do not add `class_variable_get`/`instance_variable_get` back into tests: assert
  through the introspection API (`pending_count`, `pending_ids`,
  `staged_words_count`, `in_flight_count`, `next_event_id`,
  `timestamp_parse_failures`, `cached_word_count`).
- Ingest is **at-least-once, not exactly-once** (§2.2, documented under "Ingest
  semantics" in the README). A crash with a batch in flight re-reads that batch,
  so up to one batch of events can be duplicated; committed rows are never lost.
  The bound is `MAX_INSERT_THREADS = 1`, so it cannot widen to several batches —
  but a production batch starts at 2000 lines and grows +20 per flush while
  throughput improves, with no cap and reset only by the `reset_caches` job or an
  importer restart, so the duplicate count can reach thousands. Anything counting
  events (dashboards, alert thresholds, `Statistic` rates) is approximate across
  a crash boundary. Do not "fix" this by advancing the checkpoint earlier: that
  is what makes rows losable. `test/import_syslog_crash_test.rb` pins both halves.
- Search is **prefix** matching, not `LIKE '%term%'`. The exact predicate is
  `like 'term%' escape '\'` (pins `%`/`_` to literals). How it is narrowed to be
  index-driven is **adapter-specific**, because the two adapters order `text`
  differently:
  - SQLite (BINARY collation): a `[term, term + U+10FFFF)` range. Keep the upper
    bound — without it SQLite estimates the subquery at half the table and
    re-plans to scan `events_words` through the `generated` index.
  - Postgres: the `like` alone, served by `index_words_on_text_pattern`
    (`varchar_pattern_ops`, byte-wise, collation-blind).
  **Never add a `U+10FFFF` upper bound on Postgres.** Under glibc `en_US.UTF-8`
  (postgres:17's default, and provision.sh) `strcoll` sorts U+10FFFF *before*
  ASCII letters, so the bound falls below every longer word and prefix search
  silently returns nothing — measured 60000 words by `like` vs 0 by that range.
  No sound upper bound exists there either: `en_US.UTF-8` gives trailing
  punctuation no primary weight, so the strings above `'foo-'` are unbounded
  (verified exhaustively over the 94 printable ASCII chars the tokenizer emits).
  `searchSQL` is relational division: a derived table of `(word_id, term_no)`
  joined to `events_words`, `having count(distinct term_no) = n_terms`. Resolve
  each term **once** — duplicating the subquery into `HAVING` doubles the words
  scans and cost scales with term count. Never join `words` into the
  `events_words` scan: that forces a full scan through the `generated` index
  instead of using the `(word_id, generated, event_id)` covering index.
- All SQL is parameterized: `exec_query(sql, "SQL", binds)` with **plain-value**
  binds (Rails 7.1 removed the legacy `[[type, value]]` pair form and raises
  `TypeError: can't cast Array` on it). `exec_query` normalizes unaliased aggregate
  column names, so alias them. Brakeman reports 0 SQL Injection warnings.
- Known landmines: `eval` in `scheduler.rb` and `Event#parsed`; `Math` core module
  reopened in `config/application.rb`;
  hard-coded year window `2014..2019` in `EventIngestor.storeEvent`; `Regexp.union([])` in
  `Event.recent_events` rejects every event when there are no exclusions.
- The suite is green (194 unit runs / 542 assertions, 4 cucumber scenarios). The
  assertion count rose from 534 at Rails 6.1 with no test logic changed: AS 7.1's
  `assert_difference`/`assert_no_difference` route their block through minitest's
  `_assert_nothing_raised_or_warn`, which counts 1 assertion per call. Don't treat
  that kind of delta as a regression without checking the helper internals. Bulk inserts
  raise `SQLite3::BusyException` under sqlite because the async insert thread opens a
  second connection while the main thread holds a write lock — pre-existing, PG-only path.

## Charting / asset pipeline
- Charts run on **Chart.js 4.4.7** (MIT), vendored at
  `vendor/assets/javascripts/chartjs/chart.umd.js`. It replaced a vendored
  Highcharts 4.0.4 build, which was an unlicensed commercial dependency.
- Chart.js lacks Highcharts' `plotBands`/`plotLines` and gauge series, so those
  live as plugins in `app/assets/javascripts/dad_charts.js` (`dadBands`,
  `dadGauge`, `dad_enable_x_zoom`). The five `draw_*` helpers keep their names
  and positional args: the `.js.erb` templates and dashboard tests call them.
- Gauge bands must draw in `afterDatasetsDraw`, not `beforeDatasetsDraw` — the
  doughnut track fill paints over them otherwise.
- **CI precompiles assets in development, where no JS compressor runs.** The
  production deploy is the only path that minifies, so it is the only path that
  exercises the compressor. `RAILS_ENV=production ... rake assets:precompile`
  is the command that actually catches minifier breakage.
- Uglifier was replaced by **terser** because UglifyJS 2.x is ES5-only and
  aborts on Chart.js's ES2015 output. sprockets 3.7 has no `:terser` symbol but
  `js_compressor=` accepts any object responding to `#compress`, so
  `Terser.new` is passed directly. Both gems need `execjs` (a JS runtime).
- Sass interpolates `#{...}` **even inside `/* */` comments** and fails the
  build. Never put interpolation syntax in a CSS comment.
- Chart.js sizes to its container; the `.dad-chart` class (applied by
  `dad_prepare_canvas`) supplies the height Highcharts used to bring itself.
  A class, not an id rule, because the system page builds ids at render time.
- To verify chart rendering without a browser: jsdom + `node-canvas` gives a
  real 2D context with pixel readback. Needs `ctx.canvas === element` identity,
  a `getBoundingClientRect` stub (jsdom does no layout), and `ResizeObserver`.
  Assert on the chart object returned by `draw_*`, not on `Chart.getChart`
  lookups, which go stale after `destroy()`.


## Two databases: SQLite in dev/test, Postgres in production

`config/database.yml` uses sqlite3 for development/test and the postgresql
adapter for production. This split hides adapter-specific breakage, because the
suite only ever exercises one engine.

- **Raw SQL must work on both.** Queries are written with SQLite `?` placeholders
  and routed through `SqlPlaceholders.query` (`app/models/sql_placeholders.rb`),
  which rewrites them to `$1, $2, ...` when the connection is Postgres. Postgres
  rejects `?` outright, so calling `exec_query` directly with `?` is a production
  bug that no SQLite-only run can detect. Verified on both engines: `$N` binds by
  order of appearance, so left-to-right numbering is correct on each.
- **`extract()` is Postgres-only; SQLite rejects it.** Dashboard queries bucket
  hours with `substr(cast(<ts> as text),1,13)` instead.
- **`Event.approximate_count` is Postgres-only** (reads `pg_stat_user_tables`,
  assumes `events_p*` partitions) and falls back to `Event.count` elsewhere.
- **`db/schema.rb` is checked in as the SQLite flavour.** Running
  `rake db:migrate` against a Postgres database rewrites it with
  `enable_extension` and `t.bigint` instead of `t.integer limit: 8`, which breaks
  `db:schema:load` for dev/test. Never commit a Postgres-generated schema.rb.
- CI has a `postgres` job that runs the whole suite against Postgres 17. It must
  not set `BUNDLE_WITHOUT=production`, because `pg` lives in the `:production`
  group. Cucumber stays on SQLite (its `database.yml` entry and DatabaseCleaner's
  open-transaction pattern are tuned for it).
- **`CONCURRENTLY` index builds can leave an INVALID husk, and Rails cannot see
  it.** A failed build (lock timeout, deadlock, cancel) does not roll back: the
  index stays, holding its name, marked `indisvalid = false`. `index_exists?` and
  `index_name_exists?` do not filter `indisvalid`, so they report it healthy, and a
  retry dies on `relation ... already exists` — wedging `db:migrate` and
  `provision.sh`. A husk is also invisible to the planner, so queries degrade to a
  seq scan with the suite green. Check with
  `select c.relname from pg_class c join pg_index i on i.indexrelid = c.oid where not i.indisvalid`;
  the CI `postgres` job asserts this. `AddPatternIndexToWords` self-heals its own.

### Running Postgres locally

The cluster in this sandbox listens on **TCP 127.0.0.1:5432** with role `dad` /
password `dad` (check `pg_isready -h 127.0.0.1 -p 5432` first; an older revision
of this file described a socket-only cluster on 5433 under `~/pgdata`, which is
not running here):

```bash
export RAILS_ENV=test SECRET_KEY_BASE=not_a_secret
export DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test
psql $DATABASE_URL -c 'select 1'   # or recreate: createdb -O dad dad_test
bundle exec rake db:migrate_from_scratch
bundle exec rake test && bundle exec cucumber
```

`pg` is already installable here, so no `bundle config` change is needed.
`db:migrate_from_scratch` (not `db:migrate`) is what builds the partitioned shape
the Postgres tests need.

**Never run `rake db:seed` against a shared test database.** It leaves an admin
user and seeded Jobs behind, and `SeedsIdempotencyTest` then fails on the next
full-suite run for reasons that look like a code regression but are leftover
state. If it happens, `rake db:migrate_from_scratch` and re-run.

`DATABASE_URL` must carry `host=`/`port=`; `DAD_DB_HOST` alone does not set the
port, and `postgres://user@/db` (empty host) is rejected by URI parsing.

## Credentials (do not commit)
- A GitHub PAT for `dhoelzer/DAD` is stored at `../.secrets/github_pat` relative to
  this repo (i.e. `<workspace>/.secrets/github_pat`), mode 0600 and outside version
  control. The workspace root `.gitignore` excludes `.secrets/`.
- Load it as `GITHUB_TOKEN` when GitHub API/`gh` access is needed:
  `export GITHUB_TOKEN=$(cat ../.secrets/github_pat)`.
- Never paste the token into this file, into commits, or into PR/issue text.
