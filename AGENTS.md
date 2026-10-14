# DAD — agent context

Log aggregation/monitoring app: `syslog.pl` (UDP/514 collector) → `Logs/LogStaging` →
`Logs/LogsToProcess` → `import_syslog.rb` → Postgres (`events` + `words` + `events_words`
inverted index) → Rails UI (dashboards, search, alerts, jobs, custom RBAC).
`scheduler.rb` polls the `jobs` table and `eval`s each `script`.

## Build / test (as of the reproducible-build branch)
- Toolchain: Ruby 2.7.8 + Bundler 2.4.22 (pinned in `.ruby-version` / `Gemfile.lock`
  "BUNDLED WITH"). Rails is 6.1.7.10 (`~> 6.1.0`). Ruby stays on 2.7 because Rails
  7.2+ is the first release that requires 3.x; Bundler stays on 2.4.x because 2.5+
  requires Ruby 3.x.
- `Gemfile.lock` and `db/schema.rb` are now tracked on purpose — do not re-add them
  to `.gitignore`.
- Run tests: `bundle install --frozen` (set `BUNDLE_WITHOUT=production` to skip `pg`),
  `bundle exec rake db:migrate RAILS_ENV=test`, `bundle exec rake test`,
  `bundle exec cucumber`. Use the cucumber **binary**, not `rake cucumber:ok` — the
  rake task runs cucumber in-process and minitest's autorun then dies on `--profile`.
- CI: `.github/workflows/ci.yml` (test + informational security job). `Dockerfile.dev`
  mirrors the same pinned toolchain.
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
- The suite is green (194 unit runs / 534 assertions, 4 cucumber scenarios). Bulk inserts
  raise `SQLite3::BusyException` under sqlite because the async insert thread opens a
  second connection while the main thread holds a write lock — pre-existing, PG-only path.

## Credentials (do not commit)
- A GitHub PAT for `dhoelzer/DAD` is stored at `../.secrets/github_pat` relative to
  this repo (i.e. `<workspace>/.secrets/github_pat`), mode 0600 and outside version
  control. The workspace root `.gitignore` excludes `.secrets/`.
- Load it as `GITHUB_TOKEN` when GitHub API/`gh` access is needed:
  `export GITHUB_TOKEN=$(cat ../.secrets/github_pat)`.
- Never paste the token into this file, into commits, or into PR/issue text.
