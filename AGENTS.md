# DAD — agent context

Log aggregation/monitoring app: `syslog.pl` (UDP/514 collector) → `Logs/LogStaging` →
`Logs/LogsToProcess` → `import_syslog.rb` → Postgres (`events` + `words` + `events_words`
inverted index) → Rails UI (dashboards, search, alerts, jobs, custom RBAC).
`scheduler.rb` polls the `jobs` table and `eval`s each `script`.

## Build / test (as of the reproducible-build branch)
- Toolchain: Ruby 2.7.8 + Bundler 1.17.3 (pinned in `.ruby-version` / `Gemfile.lock`
  "BUNDLED WITH"). Rails 4.2.11.3 is the ceiling: 4.2 does not boot on Ruby 3.x
  (`BigDecimal.new` removed) and `bigdecimal ~> 1.4.4` is pinned to keep it booting
  on 2.7.
- `Gemfile.lock` and `db/schema.rb` are now tracked on purpose — do not re-add them
  to `.gitignore`.
- Run tests: `bundle install --frozen` (set `BUNDLE_WITHOUT=production` to skip `pg`),
  `bundle exec rake db:migrate RAILS_ENV=test`, `bundle exec rake test`,
  `bundle exec cucumber`. Use the cucumber **binary**, not `rake cucumber:ok` — the
  rake task runs cucumber in-process and minitest's autorun then dies on `--profile`.
- CI: `.github/workflows/ci.yml` (test + informational security job). `Dockerfile.dev`
  mirrors the same pinned toolchain.

## Facts worth remembering
- Last upstream commit: 2016-10-01. Before the reproducible-build branch: `rails '> 4'`
  unpinned, no `Gemfile.lock`, no `db/schema.rb`, no CI.
- App class is `Events::Application`; DB is Postgres in production, SQLite in dev/test,
  but the code uses PG-only SQL (`pg_stat_user_tables`, `extract()`) → dev/test diverge.
- Auth is hand-rolled: `users`/`roles`/`rights` + `sessions` table + `cookies[:sessionID]`.
  Each controller overrides a public `authorized?` method (also routable as an action).
- `Event` holds all ingestion state in class variables (`@@pendingEventValues`,
  `@@nextEventID`, word/system/service caches) and builds raw multi-row INSERTs.
- Search = `LIKE '%term%'` over `words.text` joined through `events_words`, which has
  **no indexes** (the migration adding them is commented out).
- All SQL is parameterized (`exec_query` + `[[nil, value]]` binds; Rails 4.2's
  `sanitize_sql_array` is protected, and `exec_query` normalizes unaliased aggregate
  column names, so alias them). Brakeman reports 0 SQL Injection warnings.
- Known landmines: `eval` in `scheduler.rb` and `Event#parsed`; `Math` core module
  reopened in `config/application.rb`;
  hard-coded year window `2014..2019` in `Event.storeEvent`; `Regexp.union([])` in
  `Event.recent_events` rejects every event when there are no exclusions.
- The suite is green (10 unit runs / 30 assertions, 4 cucumber scenarios). Bulk inserts
  raise `SQLite3::BusyException` under sqlite because the async insert thread opens a
  second connection while the main thread holds a write lock — pre-existing, PG-only path.
