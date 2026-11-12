# DAD — agent context

Log aggregation/monitoring app: `syslog_collector` (Rust, UDP/514 collector) → `Logs/LogStaging` →
`Logs/LogsToProcess` → `import_syslog.rb` → Postgres (`events` + `words` + `events_words`
inverted index) → Rails UI (dashboards, search, alerts, jobs, custom RBAC).
`scheduler.rb` polls the `jobs` table and runs each `script` through the
`JobHandler::HANDLERS` allowlist — it does *not* `eval` it (see "Former
landmines" below; the `eval` sink is gone). `scheduler.rb` itself is only the
`while(true)` loop; the loop body is `JobScheduler.run_cycle`
(`app/models/job_scheduler.rb`), which is where per-Job fault isolation lives and
where the tests are. Keep it that way: an untestable inline loop is what let a nil
`Job#frequency` crash the process past the `rescue` (§2.4).

## Build / test (as of the reproducible-build branch)
- Toolchain: Ruby 3.3.8 + Bundler 2.6.7 (pinned in `.ruby-version` / `Gemfile.lock`
  "BUNDLED WITH"). Rails is 8.1.4.1 (`~> 8.1.0`), upgraded through 8.1.4 (tag
  `rails-8.1.4`) and now on the 8.1.4.1 patch release; the path was 7.1.6 ->
  7.2.3.2 -> 8.0.5.1 -> 8.1.4, one commit per minor step. Ruby jumped at
  the 7.1 step rather than at 7.2 because nokogiri had already dropped 2.7. 3.3.8 sits above the 7.2 (3.1) and 8.1 (3.2) floors, so no step after 7.1
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
  is kept explicit so a future json 4 cannot arrive transitively. The `sqlite3`
  gem is gone entirely: Postgres is the only engine (see "Postgres everywhere").
- `Gemfile.lock` and `db/schema.rb` are now tracked on purpose — do not re-add them
  to `.gitignore`.
- Run tests, preferred: `bin/docker-test` — the whole suite against the Compose
  Postgres, plus the schema-shape and INVALID-index assertions the CI `postgres`
  job makes. Extra args replace the container command, so
  `bin/docker-test bundle exec rails test test/models/event_test.rb` runs one file
  and `bin/docker-test bash` opens a shell in it.
- Run tests without Docker: `bundle install --frozen`, point `DATABASE_URL` at a
  Postgres cluster, then `bundle exec rake db:migrate_from_scratch` and
  `bundle exec rake test`. **`db:migrate_from_scratch`, not `db:migrate`** — see
  "Postgres everywhere". Use the cucumber **binary**, not `rake cucumber:ok` — the
  rake task runs cucumber in-process and minitest's autorun then dies on
  `--profile`.
- **`rake test` does not run `test/system`.** Railties sets `DEFAULT_TEST_EXCLUDE`
  to `test/{system,dummy,fixtures}/**/*_test.rb`, so the browser-level suite needs
  `bundle exec rake test:system` (or `bin/rails test test/system`). CI and the
  compose `test` service run both; a bare `rake test` passing says nothing about
  the rendered-HTML tests.
- `test/system/` uses **Capybara rack-test, not a real browser**. Two reasons.
  The app forces http → https outside development (`ApplicationController#ssl`),
  so a browser session has to be served over TLS. And there is no usable driver:
  `chromium-driver` is not installed and the packaged candidate (154.0.8037.57)
  does not match the installed Chromium (155.0.8059.79), so Selenium fails at
  session creation. `SystemTest` (in `test/system_helper.rb`) instead sends
  `HTTPS=on` in the request env, the way the controller tests already satisfy
  that filter. Consequence:
  **rack-test runs no JavaScript.** The dashboard's `#events`, `#stats` and
  `#*_chart` divs are empty there, so those tests assert the static shell and the
  ids the JS writes into, not the populated content. `.js.erb` output stays
  covered by `test/controllers/dashboard_render_test.rb`.
- **Ingesting inside a fixture test poisons later tests.** `EventIngestor` writes
  events, systems, services and words from background batch threads, each on its
  own database connection, which sits outside the transaction wrapping a
  transactional-fixture test. The thread's rows commit for real while the test's
  own rows roll back, leaving `events.system_id` pointing at a `systems` row that
  no longer exists — and the next test that renders that event 500s on
  `nil.display_name`. Build searchable events with
  `SystemTest#create_searchable_event`, or the way `test/controllers/xss_test.rb`
  writes `events_words` rows by hand.
- Fixture foreign keys must resolve. Fixtures get hashed ids, so a hardcoded
  `system_id: 1` dangles unless the parent fixture declares `id: 1`.
  `test/models/fixture_integrity_test.rb` enforces that; `systems`, `services`,
  `events`, `alerts` and `users` carry explicit ids for exactly that reason.
- `config/initializers/require_secrets.rb` fails the boot when `SECRET_KEY_BASE`
  is unset, so every test command needs it exported (any non-empty value in test).
- Tests that need a **second** database — the ingest tests that run the importer
  as a subprocess — create throwaway databases through
  `test/support/scratch_database.rb`. It connects over a separate raw `PG`
  connection, not the ActiveRecord one: `CREATE DATABASE` fails with
  `PG::ActiveSqlTransaction` inside transactional fixtures. That needs `CREATEDB`
  on the role behind `DATABASE_URL`.
- Tests that assert an **index is usable** go through `test/support/query_plan.rb`
  (`include QueryPlan; explain(sql, binds)`). It sets `enable_seqscan = off`
  deliberately: on a test-sized table the planner is entitled to prefer a seq
  scan, so asserting its cost choice asserts a guess. Turning scans off asks the
  question the finding was actually about — can this index serve this query shape
  at all?
- Docker: `Dockerfile` + `docker-compose.yml`. One image, separate containers for
  `db` (postgres:17), `migrate` (one-shot), `web`, `importer`, `scheduler`,
  `syslog`, and `test` (behind `--profile test`). `docker-compose.db-port.yml` is
  an optional override that publishes 5432 for host `psql`. `.dockerignore` keeps
  the build context off `log/` and `vendor/bundle` (~5.6 GB otherwise).
  Every service but `syslog` ships its own stdout/stderr to the collector
  (`x-app-logging`), so the stack watches itself and container logs become `events`
  rows under a per-container `Service` (`dad-web`, `dad-db`, ...). Two traps, both
  measured: the log driver resolves `syslog-address` in the **daemon's** namespace,
  so a compose service name (`udp://syslog:514`) cannot resolve and the container
  never starts -- use the host loopback plus the published port; and the frame
  format decides whether anything is stored, so set **no** `syslog-format` (the UDP
  default omits the hostname slot and lands the tag in the `Service` field, while
  `rfc5424` fails every timestamp parse and `rfc3164` puts the Docker host's
  hostname there instead). `DAD_SYSLOG_PORT` moves the published port and every
  driver address together. Do not add `depends_on: syslog` to `db`: a failed bind
  on 514 then takes the whole stack down.
  The `Dockerfile` was `Dockerfile.dev` and **could not build**: it had a bare
  `gem install bundler` line, which is not a Dockerfile instruction. No CI job
  built the image, so nothing caught it. It also shipped no JS runtime, which
  breaks every view render through ExecJS (CI hides this: GitHub runners have Node).
  The `migrate` service seeds `admin` when the `users` table is empty, using
  `DAD_ADMIN_PASSWORD` (default `dad_dev_password`, development only) — without it
  the stack comes up with zero users and the login form can never succeed. Do not
  seed unconditionally: `db:seed` also recreates the maintenance Jobs.
- CI: `.github/workflows/ci.yml` — six jobs: `test` (unit + `test:system` + cucumber
  against a `postgres:17` service), `assets`, `systemd`, `docker`, `collector`, `security`
  - Brakeman runs with **no ignore file** and must report 0 warnings. Its
    `ValidationRegex` check fires on `format: { with: /.../ }` whenever the regex
    is not `\A`/`\z`-anchored. For a deliberate *prefix* check (e.g. the DN
    validation on `ActiveDirectoryConnection`), write a custom `validate` method
    instead of adding an ignore entry -- `format:` implies the anchored reading to
    readers as well as to Brakeman, so the check is wrong as well as flagged.
  (three **blocking** gates: `bundle-audit`, `brakeman`, `gitleaks` over the
  working tree via `.gitleaks.toml`).
  The `test` job runs `db:migrate_from_scratch`, then asserts the partitioned
  shape really was built and that no index is left `INVALID`, before either suite.
  Those two assertions exist because plain `db:migrate` would silently test a
  schema production does not have, and a failed `CONCURRENTLY` build leaves a
  husk that `index_exists?` reports as healthy.
  The `docker` job builds the image and boots the compose stack, then asserts the
  database was migrated+seeded, that a view actually renders, that an emitted asset
  path returns 200, that a UDP packet reaches `events`, that the stack's own
  container logs reach it under three named Services, and that a Windows fixture
  reaches it on the right System. It exists because
  nothing used to build the image, which is how a Dockerfile containing a bare
  `gem install` line reached `master`. Two of its checks are only meaningful
  against the image, not runner Ruby: the JS runtime (GitHub runners ship Node, a
  bare `ruby:*` image does not).
  The boot step accepts **any** HTTP status, including 500 — its job is to know
  Rails finished booting, not that the app is healthy, so a render failure reaches
  the step that names the cause.
  **CI steps run `bash -e`, so a bare `x=$(some_command)` aborts the step if the
  command fails** — the assignment carries its exit status. This bit the boot
  poll: while Rails is still binding, the first request can be *reset* rather
  than refused, curl exits 56 with no output, and the step died on attempt one
  against a perfectly healthy stack. Guard polling commands with `|| fallback`.
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
  `RECOMMENDATIONS.md` (formerly §1.1, now the appendix) got this backwards and
  claimed account takeover. The key is burned in history but no live deployment
  holds it, so the item is closed. Rotate with `bin/rotate_secret_key_base`.
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
  200 on a real production boot. The systemd deploy never runs
  `assets:precompile`; only the CI `assets` job does.

## Facts worth remembering
- Event retention is archive-gated and, since the free-space floor, also
  destructive in two places. Rules that are not obvious from the code:
  * A partition is dropped only after `EventPartitionBackup` has written its CSV
    to `DAD_OFFLINE_STORAGE_DIR`. Never reorder that.
  * Pruning archives is **unrecoverable** — an archive is usually the only copy
    of a month the DB already dropped. It is off unless an admin sets
    `preferences.archiveFreeSpacePercent` (nil/0 = off).
  * `prune_archives` fails **closed**: if `df` cannot measure the filesystem it
    deletes nothing. Do not make that path permissive.
  * Pruning runs *before* archiving in `maintain`, and charges the projected size
    of the incoming archives against the floor. Moving it after archiving defeats
    it.
  * The setter clamps to 0..100. An unclamped 1000 reads as "keep 1000% free",
    which no filesystem satisfies, so every archive becomes prunable. The clamp
    is load-bearing, not cosmetic.
  * `partition_sizes` uses `pg_relation_size` (rows only), not
    `pg_total_relation_size` — the CSV has no indexes, so counting them
    over-estimates and deletes more history than needed.
  * `EventPartitioning.execute` cannot bind a Ruby Array to `ANY($1)` on the pg
    adapter; build a positional `IN (..., ...)` placeholder list instead.
  * Alert on the unmeetable floor only (deduped by `short_description`, not
    per run). Pruning that succeeds is configured behaviour: log it, don't alert.
  * `prune_archives` takes a `protected:` list of partitions whose archives must
    not be deleted. `maintain` passes `expired_names`: this run is about to write
    an archive for each of them, so pruning one frees bytes the next step spends
    re-writing it. Without that, a run can report a successful prune and still
    breach the floor. A manual `bin/prune_event_archives` deliberately passes no
    protected set — it is not paired with an imminent write.
  * `upcoming_archive_bytes` skips partitions that already have a complete
    archive, because `backup_partition` returns the existing file without
    re-writing it. Charging them prunes history that was never needed.
- Filesystem measurement lives in `DiskSpace` (`app/models/disk_space.rb`) and is
  shared by archive pruning and the `disk_utilization` job. Non-obvious rules:
  * It measures the filesystem holding a **given path**, via `df -Pk`. The old
    `Event.diskUtilization` grepped `df -m` for `/`, which reported the wrong disk
    whenever `offline_storage` sits on its own mount — the exact partition
    retention can fill.
  * Every failure path returns **nil**, never 0. The old `split(...)[4].to_i`
    turned a missed grep into "0% used", reading as an empty disk to an operator
    and, if it ever fed a deletion decision, authorising deleting everything.
    `disk_utilization` prints "unknown", and the dashboard helper returns nil so
    the chart is skipped rather than drawn at 0%. (The disk pie is currently
    commented out in `app/views/events/index.js.erb`, so the job is the live
    consumer; the helper is fixed with it regardless.)
  * `df -Pk` field 4 is **available**, not free: part of the filesystem is
    reserved for root and the app runs as the service user, so available is what
    bounds whether a write succeeds.
  * `parse_df_output` is split out from `measure` so malformed-df handling is
    testable against exact text. Keep it that way: mocking `IO.popen` would test
    the mock.
- Last upstream commit: 2016-10-01. Before the reproducible-build branch: `rails '> 4'`
  unpinned, no `Gemfile.lock`, no `db/schema.rb`, no CI.
- **Re-run `bundle exec bundle-audit check` — do not trust a count written here.**
  This bullet asserted "4 advisories" long after both were fixed, then "0
  advisories", which was also stale: it reached 43 across 11 gems because Rails
  8.1.4.1 shipped on 2026-11-04 while `Gemfile.lock` sat on 8.1.4. Cleared at
  `40a7ac8` by a `bundle update`, not an upgrade — the Gemfile already allows
  `~> 8.1.0`. The gate goes red on its own whenever ruby-advisory-db moves under a
  pinned lock, so this bullet will be stale again; that is why it says to re-run. The two *former* findings this bullet
  used to describe are genuinely gone: `httparty` was dropped entirely (nothing in
  app/, lib/ or test/ used it; the Gemfile keeps a comment saying so), and
  `jquery-rails` is now `~> 4.6.0` (4.6.1), past the 4.4.0 that fixed
  CVE-2020-11023/CVE-2020-23064. Neither appears in the current audit output.
- `/users` (HTML) no longer renders the bcrypt `password_hash` column (closed at
  `365c845`, RECOMMENDATIONS §1.3). PR #4 had fixed only the JSON API; the three HTML
  views were missed. `grep -rn password_hash app/views/` is empty.
- App class is `Events::Application`; the DB is **Postgres in every environment**,
  including development and test. Raw SQL is still written with `?` and routed
  through `SqlPlaceholders.query`, and the few remaining `adapter_name` checks are
  defensive (an unknown adapter chunks conservatively; an unpartitioned install
  falls back to `COUNT(*)`) rather than supporting a second engine. See "Postgres
  everywhere" below.
- Auth is hand-rolled: `users`/`roles`/`rights` + `sessions` table + `cookies[:sessionID]`.
  Access control is now **declared in constants on `ApplicationController`**, not
  overridden per controller — `def authorized?` exists exactly once, in the base class,
  and runs as a `before_action :ssl, :gatekeeper, :authorized?`. The old copy-pasted
  per-controller overrides (and their routable `authorized?` actions) were removed in
  PR #8 (RECOMMENDATIONS appendix 1.8).
- Ingestion lives in `EventIngestor` (`app/models/event_ingestor.rb`), split out
  of `Event` (§4.1). `Event` is the model and the read side only: associations,
  search, the dashboard feed. `EventIngestor` holds the write-side state in
  class-level instance variables (`@pendingEventValues`, `@nextEventID`,
  word/system/service caches, checkpoint bookkeeping) and builds raw multi-row
  INSERTs. It is process-global and assumes one long-running importer.
  `resetCaches` is the single place that state is defined and runs once at load —
  and it must stay that way. Two defects came from state that `resetCaches` did
  not initialise: `@cachelifetime` (nil, so the first `prune_words` on a long
  ingest raised `TypeError` and killed the importer — RECOMMENDATIONS §2.7) and
  the statement-parameter ceiling. If you add ingest state, add it to
  `resetCaches`.
  Do not add `class_variable_get`/`instance_variable_get` back into tests: assert
  through the introspection API (`pending_count`, `pending_ids`,
  `staged_words_count`, `pending_token_count`, `in_flight_count`, `next_event_id`,
  `timestamp_parse_failures`, `cached_word_count`).
  Note `staged_words_count` alone is not the whole staged index: uncached tokens
  are held separately until the flush resolves them, so read it together with
  `pending_token_count`.
- Uncached words are resolved **in bulk at flush time**, not per token during
  staging (RECOMMENDATIONS §3.6). `stage_event` appends `(event_id, generated,
  [tokens])` to `@staged_tokens`; `performPendingInserts` calls
  `resolve_staged_words`, which resolves the batch through `Word.resolve_ids` —
  one indexed `IN` lookup plus one `insert_all … RETURNING` per
  `Word::RESOLVE_CHUNK` tokens. This is the dominant ingest cost: 186,089 → 360
  statements and 46,515 → 67 transactions per 20k lines, 6.4× cold / 2.36× warm.
  Batch-size tuning alone cannot recover it (§2.6 exhausted that). Three things
  the shape is protecting, and which any change must keep:
  - `@staged_tokens` carries the **event id per event**, not per batch — a token
    attributed to the wrong event is a wrong search hit, and neither dropping a
    token nor misattributing one raises.
  - `resolve_staged_words` builds rows locally and appends them only once every
    token has an id, and `storeEvent`'s rollback unwinds `@staged_tokens` too.
    The importer's per-line `rescue` calls `flush_and_wait` (§5.3), so a partial
    append plus a retry duplicates index rows and search returns the event twice.
  - `words.text` has **no unique index**, so a text can have several rows.
    `resolve_ids` keeps the **lowest** id, matching the old `find_by`; a
    `pluck().to_h` keeps the highest and silently re-points ingest at a different
    row than existing `events_words` rows use.
  Truncation lives in `Word.truncate_for_column` and must be applied by both
  `stage_event` and `resolve_ids` — if lookup and storage disagree, every token
  over 255 chars re-inserts on every pass. `Word.find_or_add` is the single-token
  form of `resolve_ids`; do not re-implement it.
- A bulk INSERT is **chunked to the adapter's host-parameter ceiling**
  (RECOMMENDATIONS §2.6). `insertStatement` builds one statement; `insert_statements`
  slices a staged batch and `write_batch` runs the slices in a single transaction.
  Do not call `insertStatement` directly for a staged batch — a production-sized
  batch (default 2000 events, ~16 `events_words` rows each) needs ~96k parameters
  against Postgres' ceiling of 65535 (Int16), and past the ceiling the adapter
  raises rather than degrading.
  `bulk_insert_size` therefore means rows per *transaction*, not per *statement*,
  and can be raised freely. The suite cannot see this limit:
  `DEFAULT_BULK_INSERT_SIZE` is 1 in dev/test, so only the subprocess tests in
  `test/models/event_ingest_limits_test.rb` (RAILS_ENV=development, against a
  scratch database) cross it.
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
  `like 'term%' escape '\'` (pins `%`/`_` to literals), served by
  `index_words_on_text_pattern` (`varchar_pattern_ops`, byte-wise,
  collation-blind).
  **Never reintroduce a `[term, term + U+10FFFF)` range.** It looks like it holds
  exactly the strings starting with `term`, and it did under SQLite's BINARY
  collation, which is why it survived for years as the SQLite branch of
  `word_lookup`. Under glibc `en_US.UTF-8` (postgres:17's default) `strcoll` sorts
  U+10FFFF *before* ASCII letters, so the bound falls below every longer word and
  prefix search silently returns nothing — measured on 280k words: term `sshd`
  matched 60000 by `LIKE` and 0 by that range. It cannot be repaired either:
  `en_US.UTF-8` gives trailing punctuation no primary weight, so the strings above
  `'foo-'` are unbounded (verified exhaustively over the 94 printable ASCII chars
  the tokenizer emits). The branch is gone; the reasoning is in the comment above
  `WORD_IDS` and must not be lost with it.
  `searchSQL` is relational division: a derived table of `(word_id, term_no)`
  joined to `events_words`, `having count(distinct term_no) = n_terms`. Resolve
  each term **once** — duplicating the subquery into `HAVING` doubles the words
  scans and cost scales with term count. Never join `words` into the
  `events_words` scan: that forces a full scan through the `generated` index
  instead of using the `(word_id, generated, event_id)` covering index.
- The dashboard **search form** is a parameter-shape trap (fixed at `7e0f435`,
  RECOMMENDATIONS §2.3). `check_box "timesearch_enabled", "enabled"` always emits
  the paired hidden field, so an *unticked* box still submits
  `timesearch_enabled[enabled]=0`. Branch on the checkbox **value**
  (`EventsController#timesearch_enabled?`), never on the key's presence — a Hash
  is truthy, which is exactly how every form search once took the absolute-date
  branch with `datetime_select`'s now→now defaults and reported 0 events. Do not
  "fix" it by deleting the hidden field: that breaks the ticked case.
  `parse_datetime_params` returns **nil** on garbage fields, so check for nil
  before building a Range — `nil..nil` reaches `searchSQL` and dies on
  `nil.to_fs`. `test/controllers/search_form_test.rb` posts the browser's exact
  parameter shape; the older tests call `Event.search` directly and cannot see any
  of this.
- All SQL is parameterized: `exec_query(sql, "SQL", binds)` with **plain-value**
  binds (Rails 7.1 removed the legacy `[[type, value]]` pair form and raises
  `TypeError: can't cast Array` on it). `exec_query` normalizes unaliased aggregate
  column names, so alias them. Brakeman reports 0 SQL Injection warnings.
- Former landmines, all now gone — verified against the tree, do not go looking for them:
  `eval(job.script)` in `scheduler.rb` is replaced by the `JobHandler::HANDLERS` allowlist
  (an unknown name raises `UnknownHandler` rather than falling back to `eval`);
  `Event#parsed` goes through `DisplayRule.apply`, a directive parser, not `eval`; the
  `Math` core module is no longer reopened anywhere; the hard-coded `2014..2019` timestamp
  window is gone; and `Event.recent_events` drops blank/nil patterns before `Regexp.union`,
  so an empty exclusion list no longer empties the feed.
  Grep for `\beval(` under app/ and lib/ returns nothing.
- The suite is green on Postgres: **488 runs / 1442 assertions / 0 failures /
  0 errors / 0 skips** (verified across three `--seed` values, because the plan
  tests are order-sensitive). Zero skips is the point and is load-bearing: the
  adapter-conditional skips are gone, so a green run can no longer mean "the
  partitioned path was never exercised". cucumber is 5 scenarios / 18 steps; the
  two `@wip` alert scenarios are excluded by `config/cucumber.yml`
  (`--strict --tags "not @wip"`) and run under `cucumber -p wip`, where they are
  **pending** — their step definitions are unimplemented stubs, a pre-existing
  gap, not a Postgres failure.
  Counts drift — run the suite rather than trusting this one. The assertion count rose
  from 534 at Rails 6.1 with no test logic changed: AS 7.1's
  `assert_difference`/`assert_no_difference` route their block through minitest's
  `_assert_nothing_raised_or_warn`, which counts 1 assertion per call. Don't treat
  that kind of delta as a regression without checking the helper internals.
- Ingest tests drain the queue (`flush_and_wait`) between staging steps so exactly one
  writer is active. That is what makes them deterministic rather than racing the
  async insert thread opening a second connection while the main thread holds a
  write lock. The writing thread is still the thing under test.

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
- **The same trap applies to CSS, and it bites size comparisons.** sass-rails'
  `setup_compression` initializer sets `css_compressor = :sass` in every
  non-development environment, so a development precompile emits an unminified
  stylesheet: the same file measured 14885 bytes over 653 lines in development
  and 8888 bytes on one line in production. Always diff compiled CSS from a
  production precompile, and clear `tmp/cache/assets` too -- `rm -rf
  public/assets` alone serves you cached output.
- `app/assets/stylesheets/` is a single `application.css`; the stock
  `scaffolds.css.scss` was merged into it. There are now **no `.scss` files**,
  and `sass-rails` is still required: it provides the `:sass` `css_compressor`
  that minifies the plain-CSS bundle. Do not drop it as vestigial.
- **All narrow-screen CSS stays inside the `@media (max-width: 768px)` block at
  the end of `application.css`.** A rule placed after that block applies at every
  width and silently changes desktop rendering. `test/system/responsive_test.rb`
  asserts nothing follows the block, so a leak fails the suite rather than
  reaching master. The containment is the safety argument: the rack-test system
  suite has no layout engine, so it cannot validate responsive CSS -- it can only
  guarantee the desktop rules are untouched.
- **Never write `complete: $.ajax()` (or any `f()` call) inside a jQuery options
  object.** It invokes the function while building the object; with no options
  jQuery uses `ajaxSettings.url` = the current page, so it fires a stray XHR, and
  the returned jqXHR is then dropped because `Callbacks.add` ignores non-functions.
  CI greps the built bundle for `[A-Za-z_$]+\.ajax\(\s*\)`; the dashboard poll in
  `app/views/events/index.js.erb` is guarded in `dashboard_render_test.rb`.
- **`coffee-rails` cannot be removed** even though the app has no `.coffee` files:
  `//= require turbolinks` compiles `turbolinks-2.5.4`'s own `.js.coffee`.
- Comments in `.js.erb` are **shipped to the browser**. Use `<%# %>` for notes that
  should stay in source -- a `//` note there is part of the response and can trip
  assertions on that response.
- **Every `id` in rendered HTML must be unique.** `test/system/unique_ids_test.rb`
  scans 17 pages and fails on any repeat. Anything rendered inside a loop -- nav
  tabs, alert rows, comments -- must use a `class`, never an `id`. The alert queue
  and nav bar used per-row ids as styling hooks until this was fixed. The CSS hooks
  are now `.criticality-N`, the `.alert-*` column classes, and `li.active`.
  `#notice` belongs to the layout -- do not re-emit it in a view.
- Form error summaries render through `app/views/shared/_error_explanation.html.erb`;
  all 14 `_form.html.erb` files call it with `record: @model`. Do not inline the
  block again. The h2 noun comes from `record.model_name.human.downcase`.
- **Most models have no validations.** Only `User` and `Job` do, and
  `config/application.rb` deliberately omits `config.load_defaults`, so
  `belongs_to_required_by_default` is off and a blank `Alert`/`Display`/`System`/
  `Service` saves cleanly. Do not assume a form can report an error, and do not
  "fix" the missing `load_defaults` without checking every `belongs_to`.
- The nav bar is generated from `$_models` (19 tabs) and the alert queue uses
  fixed `display:table-column` widths summing to 1140px. Both are wider than any
  phone; that is why the media query exists. Adding a model adds a nav tab.
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


## Postgres everywhere

`config/database.yml` uses the postgresql adapter for development, test and
production. SQLite was dropped as the dev/test engine, and the reason is not
taste: while the split existed, `Event.insertStatement` emitted SQLite `?`
placeholders through `exec_query`, Postgres rejected them outright, and
production could not insert a single event while every CI job stayed green
(RECOMMENDATIONS 3.2). `pg` also sat in the `:production` Gemfile group, so any
job that set `BUNDLE_WITHOUT=production` silently lacked the driver it needed.
`events`/`events_words` are range-partitioned and are **not partitionable at all**
on SQLite, so a SQLite suite never exercised the shape production queries, and the
composite covering index on `events_words` is Postgres-only.

`bin/docker-test` is the zero-configuration path: it brings up the Compose `db`,
runs both suites, and makes the same two schema assertions the CI `test` job makes.

- **Raw SQL is still written with `?`** and routed through
  `SqlPlaceholders.query` (`app/models/sql_placeholders.rb`), which rewrites to
  `$1, $2, ...`. Calling `exec_query` directly with `?` is the exact bug that
  shipped 3.2. `$N` binds by number, so left-to-right numbering is correct.
  Known limitation: Postgres also uses `?` as the jsonb key-existence operator;
  nothing here queries jsonb, and if it ever does that query needs its own path.
- **`extract()` is avoided** in favour of `substr(cast(<ts> as text),1,13)`. It
  was a portability constraint and is now just the form the dashboard uses.
- **`Event.approximate_count`** reads `pg_stat_user_tables` and assumes
  partitioned `events_p*`. It falls back to an exact `Event.count` when the sum
  comes back null — i.e. on an install whose partitioned shape was never built.
  That fallback is tested; do not remove it as "dead SQLite support".
- **`db/schema.rb` is a portable, NON-partitioned dump.** It cannot express
  `PARTITION BY`/`PARTITION OF`. It is what the subprocess tests load into a
  scratch database (they want the tables without the partition machinery), and it
  is *not* the schema production runs.
  - `config/environments/test.rb` sets `dump_schema_after_migration = false`, so a
    test migrate never rewrites it. If it ever must be regenerated, do it
    deliberately and re-read the diff: a Postgres dump would silently drop the
    partitioning while still looking complete.
  - **Adding a migration leaves `schema.rb` stale**, because nothing regenerates it
    automatically (see above). A fresh `db:prepare` then silently skips the new
    tables. Regenerate with `RAILS_ENV=development bin/rails db:migrate`, but
    expect the dumper to also reformat unrelated tables (`t.integer limit: 8` ->
    `t.bigint` across 18 tables as of PR #42). If you hand-insert just the new
    blocks to keep the diff reviewable, you must also hand-insert the matching
    `add_foreign_key` lines -- `t.references ... foreign_key: true` emits them in
    a separate section at the bottom of the file, and missing them loses the
    constraints silently. Verify by loading the result into a scratch database and
    counting tables and `contype='f'` constraints.
  - `maintain_test_schema = false` for the same reason. Rails purges and reloads
    `schema.rb` before a run when a migration is newer than the dump, which would
    install the non-partitioned shape over what `db/migrate` built. This used to
    be conditional on `DATABASE_URL` matching `postgres://`; it cannot be, because
    Postgres is now the default in `database.yml`, so the common case is
    `DATABASE_URL` being **unset** and the old condition evaluated to true.
- **Prepare the test database with `db:migrate_from_scratch`, never `db:migrate`.**
  `db:migrate` loads the committed `schema.rb` dump into an empty Postgres
  database and skips `db/migrate` entirely, so the partitioned shape is never
  built and the partitioning/backup/index tests fail in ways that look like app
  bugs. `bin/docker-test`, the compose `migrate` service and CI all use the
  from-scratch task.
- Cucumber runs against the same Postgres. `features/support/env.rb` whitelists
  the Compose URL in `DatabaseCleaner.url_whitelist` **before** setting
  `strategy = :transaction` — DatabaseCleaner refuses a non-localhost URL at
  strategy assignment time (the cleaner runs its safeguards in its constructor),
  so whitelisting after the assignment raises instead of cleaning. Whitelist that
  one URL rather than clearing `allow_remote_database_url`, so a hand-set
  `DATABASE_URL` aimed at a real server still fails loudly.
- **`CONCURRENTLY` index builds can leave an INVALID husk, and Rails cannot see
  it.** A failed build (lock timeout, deadlock, cancel) does not roll back: the
  index stays, holding its name, marked `indisvalid = false`. `index_exists?` and
  `index_name_exists?` do not filter `indisvalid`, so they report it healthy, and a
  retry dies on `relation ... already exists` — wedging `db:migrate`. A husk is
  also invisible to the planner, so queries degrade to a seq scan with the suite
  green. Check with
  `select c.relname from pg_class c join pg_index i on i.indexrelid = c.oid where not i.indisvalid`;
  the CI `test` job and `bin/docker-test` both assert this.
  `AddPatternIndexToWords` self-heals its own.

### The syslog collector (Rust)

`syslog_collector/` is a zero-dependency crate (std only, so there is no supply
chain to audit and `Cargo.lock` never changes — it is committed as the record that
there are no dependencies). It replaced `syslog.pl`; the Perl file is gone.

Build/test it on its own: `cd syslog_collector && cargo test` (26 unit + 13
integration). The integration tests spawn the real binary on high UDP ports and
compare bytes on disk, so they need no root and no Postgres. The CI `collector`
job runs `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and
`cargo test`. Keep the toolchain pinned in lockstep across two places: the
`rust:` tag in `Dockerfile` and `dtolnay/rust-toolchain` in `ci.yml`.

**The record format is the contract.** `format_record` writes
`<source-ip> <message>\n`. `EventIngestor` stores that line whole in
`events.hunks`, and `Event#event_fields` splits it on spaces, so the source IP is
field 1 and the syslog timestamp follows it. Changing the format breaks the
read side, not just the write side.

**The transform is byte-oriented (`&[u8]`, never `String`) on purpose.** Perl
never decoded, so a payload with invalid UTF-8 reached `hunks` verbatim. Decoding
in the collector would corrupt it. `EventIngestor` does the UTF-8 scrubbing, and
that is where the decision belongs.

**Rotation is traffic-driven, not timer-driven.** `ensure_open` is called from the
per-message path, so with no traffic the open file is never moved. This is why a
single probe packet into a quiet stack sits in `LogStaging` until a *second*
packet arrives after the 60s boundary — the CI `docker` job sends two packets for
exactly this reason.

**Three deliberate departures from Perl, all because Perl lost data.** Measured,
not assumed:
- Perl block-buffered stdio and had no signal handler: 40 messages sent, **0 bytes
  durable** after SIGTERM *and* after SIGKILL. The Rust collector flushes per
  record (costs nothing: ~400k msgs/s vs Perl's buffered write path).
- Perl left the in-flight file stranded in `LogStaging` on every restart, and
  **nothing ever reads `LogStaging`** — so up to 60s of logs were orphaned
  permanently, including on a planned `systemctl restart`. `recover_orphans()`
  claims them at startup. Startup rather than a SIGTERM handler is deliberate: a
  handler cannot run on SIGKILL, OOM kill, or power loss.
- Perl's `recv($buf, 1540)` silently truncated anything larger (a 3000-byte packet
  yielded exactly 1540). The cap is now 65507, the max UDP payload. `hunks` is a
  `:text` column, so this needs no schema change.

Everything else is byte-identical to Perl, verified by running both collectors on
UDP/514 against the same 22-packet corpus: the rotated file the importer reads was
the same 2116 bytes with the same SHA-256. That equivalence is *not* automated —
if you change the parse, re-verify against the record format by hand.

### The path coupling between the collector and the importer

`syslog_collector/src/runtime.rs` hardcodes `DEFAULT_STAGING="/var/DAD/Logs/LogStaging"`
and `DEFAULT_PROCESSING="/var/DAD/Logs/LogsToProcess"`. `import_syslog.rb` uses paths
**relative to its own working directory**: `Dir.chdir('Logs/LogsToProcess')`, then
`PROCESSED_DIR = '../ProcessedLogs'`. The two agree only because every systemd unit
sets `WorkingDirectory=/var/DAD`. Nothing validates that they line up, so change
the working directory (or the image `WORKDIR`) and the collector keeps accepting
UDP packets and writing into a tree the importer never reads — silently, with no
error anywhere. `Dockerfile` therefore uses `WORKDIR /var/DAD`, not `/app`.

Rotation is **traffic-driven**, not timer-driven: `ensure_open` runs from the
per-message path, so with no inbound traffic the open staging file is never moved
into `LogsToProcess` and the importer sees nothing. A quiet system looks like a
broken importer, and a single probe packet sits in `LogStaging` until a *second*
packet arrives after the 60s boundary — the CI `docker` job sends two for this
reason.

The collector flushes each record as it writes, so the staging file is readable
immediately. The Perl collector it replaced block-buffered `print LOG` and left
the file at 0 bytes until rotation's `close(LOG)`; older notes called that
"buffering, not data loss" and it was **wrong** — measured, 40 messages left 0
bytes durable after SIGTERM *and* SIGKILL. See "The syslog collector (Rust)"
above.

### The Windows ingest path (OpenWEC)

`lib/windows_events.rb` converts OpenWEC records into the staging record format;
`lib/windows_forward.rb` is the tail/queue machinery; `import_windows_events.rb`
is the daemon an operator runs (`dad-windows`, compose profile `windows`).

**The converter exists so the ingestor does not change.** `stage_event` already
parses an RFC 3339 timestamp as one token, so a converted line needs zero importer
edits and inherits word indexing, batching, checkpointing and partitioning. A
second ingest path would have reimplemented all of that and drifted. The converter
is Ruby, not Rust, because Nokogiri is already a dependency and `syslog_collector`
is deliberately zero-dependency (see above) — putting XML parsing there would
break that property for no gain.

**One queue, one importer.** The forwarder enqueues into `LogsToProcess`; it does
not import. `dad-importer` owns claim/checkpoint/batch. A second importer would
race the first for the same files.

**Never point OpenWEC at `Logs/LogStaging`.** `recover_orphans()` moves *every*
file in that directory into `LogsToProcess` at collector startup, on the stated
assumption the collector is the only writer there. A converter appending there
would have its in-progress file renamed away mid-write. Hence `Logs/Windows`
(OpenWEC's output) and `Logs/WindowsStaging` (the forwarder's buffer) are new,
separate directories.

**Staging must differ from the queue.** `LogQueue.pending` globs `*` and excludes
only `.processing` and `.offset` names, so a half-written file in the queue
directory would be claimed and read mid-append. The forwarder writes to staging,
`fsync`s, then renames into the queue; the rename is what publishes the file.
`Writer.new` raises `ArgumentError` if the two directories are the same.

**One record is not one line.** OpenWEC's Files driver appends one newline per
record for `Json`/`Nxlog`/`JsonRaw`, but a `Raw` record's `RenderingInfo/Message`
can contain literal newlines, so a line-based tail would split one 4688 into a
dozen garbage events that are indistinguishable from real data once stored.
`Reader` reads byte chunks and splits on record boundaries (`<Event`..`</Event>`
for XML, newline for JSON). Its offset advances only past records actually
yielded, so a partial record is resumed, not skipped. The offset is written
*after* the flush: at-least-once, never at-most-once.

**Field keys are downcased in every format; values keep their case.** Otherwise
the same event arriving as `Json` versus `Nxlog` displays under two spellings.
The word index downcases regardless, so this only affects `hunks` in the UI and
in exports.

**Timestamps are normalised to RFC 3339 with a literal `Z`.** A `+` offset
becomes a space under `stage_event`'s sanitiser, which splits the timestamp
across two tokens and mis-locates the service name (the service is read at
`1 + consumed`, so the timestamp's token count is load-bearing).

**Fixtures are hand-authored.** OpenWEC ships no event fixtures and its CI has
none worth reusing. `test/fixtures/windows_events/` holds 10, including a
multi-line `Raw` record (the framing trap) and three malformed cases. They are
transcribed from the OpenWEC format docs, not captured from a live WEC, so they
are a *format* contract, not a byte-exact upstream capture. If OpenWEC changes
its output, re-derive them from a real collector.

**CI**: the `docker` job boots the `windows` profile, copies a fixture in as
`openwec.log`, and asserts a row lands in Postgres on the right `System`. The
`systemd` job's `dad-*.service` glob picks up `dad-windows.service` with no
workflow change.

### Running Postgres locally

Prefer Docker: `bin/docker-test` (suite) or `docker compose up` (stack). For a
local cluster, the one in this sandbox listens on **TCP 127.0.0.1:5432** with role
`dad` / password `dad` (check `pg_isready -h 127.0.0.1 -p 5432` first; an older
revision of this file described a socket-only cluster on 5433 under `~/pgdata`,
which is not running here):

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

## Windows collection: two paths, one pipeline

DAD polls Windows hosts itself (`wevtutil` over WinRM) and also still supports the
OpenWEC push path. **Both converge on the same staging line and the same
`LogsToProcess` queue**, so everything below `WindowsEvents.convert` is shared.
Keep that property: the original design decision was to convert Windows events
into the format the ingestor already accepts rather than teach the ingestor about
Windows, and it is what makes each new source a bolt-on instead of a fork of the
ingest path. Do not add importer changes for a new source.

The poller is a `Job` (`poll_windows_events`), not a daemon -- it runs inside
`dad-scheduler`, so it needs no new unit, container, or `Logs` volume.

Two numbers that are deliberately different, and easy to misread as a bug:
- the **Job `frequency`** (60s) is only how often the due-list is swept;
- the **per-host interval** is computed from its `PollingPriority` band and its
  EMA-smoothed event rate: `clamp(500 / eps, band_min, band_max)`, applied only
  when the change is >=25% off (deadband), and a zero rate takes the band's
  *slowest* interval -- dividing first gives `Infinity`, and `Infinity.round`
  raises `FloatDomainError`.

Scheduling state lives in the `windows_targets` row, not memory: the scheduler
runs under `Restart=always`, and a crash between polls must not reset a measured
rate.

`WindowsPoll.poll` must **never raise** for a host-level failure. An exception
there aborts the cycle and skips every remaining target in a fleet of hundreds.
Record the failure in `last_status` and reschedule at the band's slowest interval.
Likewise a failing *channel* must not lose the host's other channels, and
wevtutil's exit code must be checked (3 = unknown channel, 5 = access denied) --
reporting those as "no events" makes a permission-locked channel look quiet.

The WinRM transport sits behind `#run_command` because there is no Windows host in
CI. Test the parsing, delta-query and queueing logic against recorded `wevtutil`
XML; do not mock the parts that can actually be wrong.

## Production boot is fail-closed on the encryption keys

`config/application.rb` raises in production unless `DAD_AR_ENCRYPTION_KEY` and
`DAD_AR_ENCRYPTION_SALT` are both set, because a `WindowsTarget` row holds a domain
credential and silently falling back to plaintext is worse than not booting.
Rails 8.1 requires the salt whenever encryption is configured.

**Any CI step that sets `RAILS_ENV=production` needs dummy values for both**, the
same way it already supplies a dummy `SECRET_KEY_BASE`. The `assets` job does this
and broke when the check landed. Verify both directions when touching this: with
the dummies `rails runner` prints `boot ok`, and without them it still raises.

Rotating those keys makes stored Windows credentials unreadable -- there is no
re-derivation path. They are deliberately *not* in `bin/rotate_secret_key_base`,
unlike `SECRET_KEY_BASE`, which is safe to rotate (sessions are DB rows).

Windows target input (address, channel names) is validated against strict patterns
rather than escaped: the `wevtutil` command line is built for **cmd.exe**, whose
quoting rules are not the ones Ruby's escaping assumes. Never switch these to
shell-escaping.

## The wiki is a separate git repo

`https://github.com/dhoelzer/DAD.wiki.git` clones to `<repo>.wiki` and is a normal
git repo -- commit and push it directly (wikis have no PR mechanism). It needs its
own local `git config user.name/email`; the clone has none. Keep it in sync with
the code: it duplicates the Jobs handler table, the env-var table, the rights
tables, the paginated-screen list, and test counts, all of which go stale.

## Credentials (do not commit)
- A GitHub PAT for `dhoelzer/DAD` is stored at `../.secrets/github_pat` relative to
  this repo (i.e. `<workspace>/.secrets/github_pat`), mode 0600 and outside version
  control. The workspace root `.gitignore` excludes `.secrets/`.
- Load it as `GITHUB_TOKEN` when GitHub API/`gh` access is needed:
  `export GITHUB_TOKEN=$(cat ../.secrets/github_pat)`.
- Never paste the token into this file, into commits, or into PR/issue text.
