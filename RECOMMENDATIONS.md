# DAD — Code Review & Improvement Recommendations

Originally reviewed at commit `db5c6b4` (last commit: 2016-10-01). Re-measured
2026-10-14 at `104abd4`: **3,470 lines** of app/lib Ruby across 18 controllers and
22 models, plus 1,885 lines of tests. **Read §7 first** — it supersedes §6 and
records two regressions that a green CI does not catch. Standalone ingestion is `import_syslog.rb`
at the repo root; `syslog.pl` and `scheduler.rb` are gone.

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

## 0a. Status update: item 1 (reproducible, patched build + CI) is done

Landed on branch `reproducible-build-and-ci` (base `db5c6b4`). The app now installs,
boots, and runs a green test suite from a clean checkout.

**Reproducibility**
- `Gemfile` pins `rails '~> 4.2.11'` (was `'> 4'`, which resolved Rails 8 against
  Rails-4-era code). Every other gem pinned to a compatible line.
- `Gemfile.lock` and `db/schema.rb` are now committed (both were gitignored);
  `.ruby-version` pins Ruby 2.7.8; `Gemfile.lock` pins Bundler 1.17.3.
- **[correctness] `schema.rb` was not reproducible.** `create_events` and
  `add_generated_to_events_words` passed `:default => Time.now`, so the column
  default was the wall-clock time of whichever run created it: every
  `rake db:migrate` rewrote `schema.rb`, and any insert that omitted
  `generated` silently got a 2014/2015 timestamp. Migration
  `20261013000001_fix_generated_column_defaults` drops the dead default
  (nothing in the app relies on it) so `NOT NULL` surfaces the mistake;
  `schema.rb` is now byte-identical across fresh migrations.
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

## 0b. Status update: item 2 (parameterise all SQL) is done

Landed on the same branch. **Brakeman's SQL Injection warnings went from 11 to 0**
(total warnings 18 → 7; the remainder are 3 XSS, 2 unmaintained deps, 1 session
setting, 1 CSRF).

- `Event.searchSQL` now returns `[sql, binds]` built purely from `?` placeholders;
  `search`/`search_period` call `connection.exec_query`. `params[:search_terms]`
  can no longer reach the SQL text, and `sanitize_sql_like` makes `%`/`_` in a
  query literal rather than wildcards.
- `System#events_since`, `System#hourly_stats`, `System#events_per_hour` and
  `System.reportingInLastDays` bind their arguments. The two identical
  `System` queries are now one `System.hourly_counts` helper.
- The five duplicated `ApplicationHelper` statistics queries collapse onto a
  single `statistics_by_hour` helper; the aggregate is looked up in a frozen
  `AGGREGATES` map instead of being interpolated.
- **`search2` / `iterativeSQLBuilder` deleted** (dead, unreferenced, and the
  worst injection sink in the repo — it recursed unbounded user-derived SQL).
- **The bulk ingestion INSERTs are parameterized.** `storeEvent` stages rows as
  hashes and `Event.insertStatement` emits one multi-row `INSERT ... VALUES
  (?, ?, ...)` plus binds. This also **removes the `hunks.gsub!("'", %q("))`
  data-mangling** from §2.5: log text is now stored verbatim, single quotes and
  all. Batching is preserved (SQLite accepts >98k host parameters; production
  PostgreSQL is higher).
- Regression tests in `test/models/event_test.rb` (10 runs / 30 assertions)
  cover placeholder-only SQL, injection payloads, LIKE-wildcard escaping,
  quote fidelity, and multi-flush bulk inserts.

Not addressed here, and worth knowing: the async insert thread opens a second
SQLite connection while the main thread holds a write lock, so bulk inserts
raise `SQLite3::BusyException` under the sqlite dev database. That is
**pre-existing** (verified identical on the original code) and does not affect
the PostgreSQL deployment; §2.4 covers the real fix.

---

## 0c. Status update: item 3 (index the search path) is done

Landed on the same branch. **Search is 1.2–2.1x faster than the original upstream
query, and ~3x faster than the interim §0b rewrite**, with byte-identical result
sets verified across 863 generated queries.

Benchmark: 50,000 events / 350,000 `events_words` rows / 5,573 distinct words,
30-day window, best of 3, sqlite.

| query | upstream `db5c6b4` | after §0b | now |
|---|---|---|---|
| `failed` | 9.2 ms | 124.7 ms | **4.3 ms** |
| `failed connection` | 4.7 ms | 139.0 ms | **3.7 ms** |
| `svc1` | 45.4 ms | 140.1 ms | **21.4 ms** |
| `10.0` | 102.0 ms | 157.0 ms | **49.4 ms** |
| `user id svc` | 136.1 ms | 195.7 ms | **113.7 ms** |

Worth being explicit about: **the §0b rewrite was a performance regression**
(9 ms → 125 ms for a single term). It fixed the correctness bug in §1.1 — counting
distinct matching `word_id`s hid any event where one term was a prefix of another
word — but it did so by joining `words` into the scan, which forced a full scan of
every join row in the time window. That is the number the table above's middle
column records, and it is why this item mattered more than it first looked.

What changed:

- **`index_events_words_on_word_id_and_generated_and_event_id`**
  (`db/migrate/20261013000002`). Built `CONCURRENTLY` on PostgreSQL via
  `add_index ..., algorithm: :concurrently` behind an `index_algorithms.key?(:concurrently)`
  guard, with `disable_ddl_transaction!`, so the build does not take a write lock on
  `events_words` and stall ingestion. Verified up **and** down against a populated
  350k-row table, and on PostgreSQL 17 directly.
- **`searchSQL` restricts `events_words` on `word_id` via a subquery** instead of
  joining `words` in. That is what makes the new index usable: the plan is now
  `SEARCH events_words USING COVERING INDEX ... (word_id=? AND generated>? AND generated<?)`,
  so SQLite reads only the rows for matched words and never touches the heap.
- **The dictionary lookup is a range, not a `LIKE`.** `LIKE 'term%'` cannot drive a
  B-tree scan, so the term→`word_id` lookup is `text >= term AND text < term + U+10FFFF`.
  A `LIKE ... ESCAPE '\'` is kept *alongside* the range: the range is only a
  narrowing filter, and under a punctuation-insensitive collation the range for
  `ab` would admit `a-b`. The `LIKE` pins literal-prefix semantics on every adapter.
- **`search`/`search_period` return a relation over a subquery** rather than
  materialising every matching id into `id in (?)`. A broad search previously bound
  ~50,000 parameters; PostgreSQL caps a statement at 65,535, so this was a latent
  crash on the real deployment at roughly 1.3x the benchmark's data volume. It is now
  one statement with 15 binds regardless of match count.
- **A latent `LIKE`-escaping bug from §0b is fixed.** `sanitize_sql_like` escapes
  `_` and `%` with a backslash, but SQLite's `LIKE` has **no default escape
  character**, so searching the term `foo_bar` matched nothing at all. The queries
  now say `escape '\'`. `index_words_on_text` and `index_events_on_generated`
  already existed, so §3.1's third suggested index was already present.

Tests added (14 runs / 49 assertions): placeholder/binding counts, the covering-index
plan assertion, index existence, literal `_` matching, and that `ab` does not match
`a-b`. Verified on a clean clone: `bundle install --frozen`, migrate, tests, cucumber
(4 scenarios), and `schema.rb` byte-stable.

Deliberately **not** done here: §3.2 (`tsvector` + GIN) is the right long-term shape
and would retire `words`/`events_words` entirely — one join row per token per event is
the dominant write and storage cost. This item is the cheap fix that makes the current
model fast; §3.2 is the fix that makes it scale.

---

## 0d. Status update: item 1.2 (remove the `eval` sinks) is done

Both sinks are gone; no Ruby from the database is evaluated anywhere in the app.

**Jobs.** `Job#script` is no longer a script -- it names an entry in a closed
registry, `JobHandler::HANDLERS` (`app/models/job_handler.rb`). `scheduler.rb`
looks the name up and calls it; an unrecognised name raises `UnknownHandler`
rather than falling back to evaluation. `Job` validates that the name is
registered, and the Jobs form is now a `<select>` over `JobHandler.names` -- the
CodeMirror Ruby editor is gone, so there is no path from the UI to arbitrary
code. Four handlers are registered (`prune_words`, `reset_caches`, `reset_stats`,
`disk_utilization`); adding capability means editing code and deploying, which is
the point.

**Displays.** `Display#display_script` is now a declarative, line-oriented spec
(`fields 1,2,5`, `regex PATTERN`, `label 3=proto:`, `join ,`) interpreted by
`DisplayRule` (`app/models/display_rule.rb`). `Event#parsed` calls
`DisplayRule.apply` instead of `eval` + `parse_event`. Specs are validated on
save, and a spec that fails to parse degrades to returning the raw line rather
than raising, so a bad rule cannot break the dashboard.

**Existing rows.** `20261014000001_retire_legacy_job_scripts.rb` clears `script`
and nulls `next_run` on every pre-existing Job. Those rows held Ruby that cannot
be translated into handler names, and leaving them would have made the scheduler
raise and fire a Critical Alert every cycle forever. The migration is
irreversible by design.

**Tests.** 27 new tests: `DisplayRuleTest` (grammar, edge cases, and an explicit
"Ruby in a display script is never evaluated" assertion), `JobHandlerTest`
(registry + `Job` validation), and functional `JobsControllerTest` /
`DisplaysControllerTest` that POST Ruby through the real forms and assert both
that the record is not created and that no marker file appears on disk. Suite is
41 runs / 106 assertions / 0 failures; cucumber 4/4; Brakeman unchanged at 7 with
no `Evaluation` findings.

**Residual risk.** `Display#key` is still compiled with `Regexp.new` on
operator input, which is a ReDoS vector (not code execution) -- tracked under
§2.6. The `Taskmaster` and `Detective` rights are no longer equivalent to RCE,
so the trust boundary described in §1.8 is much less sharp than it was.

## 0e. Status update: the Postgres-only dashboard queries are portable and now tested

**The gap.** `index.js.erb` and `systems/show.js.erb` call the statistics
helpers directly, and those helpers bucketed by hour with `extract(year from
...)`. `extract()` is Postgres-only; SQLite rejects it outright (`near "from":
syntax error`). Since CI runs SQLite, **both pages raised on every dev, test,
and CI run** -- the suite never rendered them, so nothing in the repo could
tell you the dashboard was broken. Confirmed by probe before the fix: `GET
/events.js` and `GET /systems/:id.js` both raised
`ActionView::Template::Error`.

**Why not just add a Postgres CI job?** Tried it, and it does not work on this
stack. Rails 4.2's `reset_pk_sequence!` reads `increment_by` from the sequence
(`postgresql/schema_statements.rb:339`), a column **removed in PostgreSQL 10**;
against PG 17 every fixture load fails (`column "increment_by" does not
exist`) -- 59/59 errors. And the pinned `pg 0.21.0` no longer compiles on Ruby
2.7 (GCC treats `rb_rescue`'s pointer mismatch as a hard error), while the
`pg 1.x` that does compile is rejected by the adapter, which requires
`pg ~> 0.15`. A Postgres job means upgrading Rails first (§4.1). Portable SQL
is the fix that is actually available today.

**The fix.** Both queries now bucket with
`substr(cast(<ts> as text), 1, 13)`. Both engines render a timestamp as
`YYYY-MM-DD HH:MM:SS[.ffffff]`, so the first 13 characters name the hour on
either one. Verified against a real PostgreSQL 17: the new query returns
identical buckets and aggregates to the old `extract()` version. Chart labels
are unchanged (`10/14/2026 7:00:00`), produced by the new
`ApplicationHelper.chart_label`.

`Event.approximate_count` was the other Postgres-only call in the render path
(`pg_stat_user_tables`); it now uses the planner estimate on Postgres and
falls back to `Event.count` elsewhere -- including on an unpartitioned Postgres
install, where the old code returned `nil.to_i` and silently reported zero
events.

**Tests.** `test/controllers/dashboard_render_test.rb` renders both real
endpoints and feeds the response to `node --check`, so a broken JS literal
fails the build rather than the browser. Reverting the fix makes these tests
fail with the original `SQLException`, so they genuinely pin the behaviour.
Suite: 64 runs / 206 assertions / 0 failures; cucumber 4/4; Brakeman unchanged.

**Found on the way, not fixed.** `daily_insert_average` returns `NaN` when its
window has no samples (`Math.mean([])` divides by zero), which renders as a
literal `NaN` in the `insert_rate` chart -- harmless-looking, but Highcharts
plots nothing and the baseline is lost. `Math.mean/variance/standard_deviation`
have no empty guard; see §5.2.

## 0f. Status update: §2.2 (timestamp parsing) is fixed, and it was worse than described

**What the section claimed.** A hard-coded 2014-2019 window, with out-of-window
dates stamped with the *current* year.

**What it actually did.** `DateTime.parse("jun 01 2023 2026 GMT")` takes `2023`
as the year and discards the appended current year, so the year survived by
accident. What got destroyed was the **time of day**: every dated line outside
the window was stored at `00:00:00`. Measured on the pre-fix code:

| input | stored `generated` | stored service |
|---|---|---|
| `Jun 01 2015 12:34:56` | `2015-06-01 12:34:56` | `sshd` |
| `Jun 01 2026 12:34:56` | `2026-06-01 `**`00:00:00`** | `sshd` |
| `Jun  1 12:34:56` (classic) | `2026-06-01 12:34:56` | **`""`** |
| `2026-06-01T12:34:56.123Z` | `2026-06-01 12:34:56` | **`""`** |
| `2026-06-01T12:34:56Z` | `2026-06-01 12:34:56` | **`"hi"`** |
| `2026-06-01T12:34:56+00:00` | `2026-06-01 12:34:56` | **`""`** |

Two defects the original write-up missed, both visible in the table:

- **Service attribution was wrong for every format but one.** `service_offset`
  was hard-coded to `5`, but the service follows the timestamp, so its index
  depends on how many tokens the timestamp consumed. Classic syslog puts it at
  `4`; index `5` is the PID, which `tr("^a-zA-Z\-_/","")` reduces to `""`.
  The most common syslog format in the wild was filing every event with no
  service. `...T12:34:56Z` read index `5` as a *message word* (`"hi"` above).
- **The ISO regex required exactly three fractional digits and a literal `Z`.**
  rsyslog's `RFC3339timestamps` emits `2026-06-01T12:34:56Z` and
  `...+00:00`; neither matched.

**Fix.** `Event.parse_timestamp` recognizes four formats and returns the token
count alongside the timestamp, so `service_offset` is derived rather than
assumed. The year window is gone. RFC 3339 offsets are normalized to UTC,
because the value is stored with `to_s(:db)`, which drops the offset. Note the
sanitizer replaces `+` with a space, so a `+HH:MM` offset arrives as a second
token and is rejoined; `-HH:MM` survives attached.

Unparseable lines are still dropped -- a live feed must not stop on a bad line
-- but they are now counted and reported at flush instead of vanishing.

**Tests.** `test/models/timestamp_parsing_test.rb`, 12 cases through the real
`storeEvent` path. Reverting the fix fails 11 of 12.

Suite: 89 runs / 274 assertions / 0 failures; cucumber 4/4; Brakeman unchanged
at 3.

**Still open.** Historical rows already stored at `00:00:00` are not repaired
by this change; `hunks` retains the raw line, so a backfill re-run is possible.

## 0g. Status update: §2.1 was misdiagnosed; the real bug is a blank pattern

**What the section claimed.** `Regexp.union([])` returns `/(?!)/`, "which matches
at every position", so an empty `exclusions` table empties the dashboard.

**That is backwards.** `/(?!)/` is a negative lookahead that never succeeds -- it
matches *nothing*. Verified directly:

```ruby
Regexp.union([])          # => /(?!)/
"anything" =~ /(?!)/      # => nil
```

Measured against the real method with an empty `Exclusion` table and 200 events,
the feed returned all 10 requested rows. The empty-table path was never broken.

**The actual trigger is a blank pattern.** `Regexp.union([""])` is `//`, which
*does* match every line. `Exclusion` has no validations and the form has no
default, so submitting it without typing a pattern stores `""` and empties the
dashboard for **every** user -- the symptom §2.1 described, reached by a
different route. Reproduced on the pre-fix code: 30 events seeded, one blank
exclusion, feed returned **0**.

**The growth loop is real, but it is not caused by the empty table.** With
fewer than 50 events on an install, `events.count < 50` is permanently true, so
N grows on every poll and compounds once past 10%:

```
poll 0..11 -> 11, 12, 13, ... 20, 22, 24      # 7 events total
```

It never converges, and the dashboard polls repeatedly. The fix stops growth
when the fetch was not truncated (the table is simply that small) and caps N at
`DASHBOARD_MAX_EVENTS = 1000` for the genuinely noisy case.

**Found on the way, not fixed.** Two more `Exclusion` defects, both left alone:

- `pattern` is documented as a regex in the model and views, but
  `Regexp.union` escapes metacharacters, so patterns are matched **literally**:
  `sshd.*fail` matches those seven characters, not `sshd` ... `fail`. A test
  pins the current behaviour; whether to change it is a product decision.
- A `nil` pattern raises `TypeError: no implicit conversion of nil into String`
  inside `Regexp.union`, breaking the dashboard for everyone. Unreachable via
  the form (it posts `""`), but reachable through the JSON API. Blank patterns
  are now filtered out, which incidentally covers `nil` too.

**Tests.** `test/models/recent_events_test.rb`, 9 cases. Reverting the fix
fails 4 of them.

Suite: 98 runs / 285 assertions / 0 failures; cucumber 4/4; Brakeman unchanged
at 3.

## 1. Do this first: the app is remotely exploitable

This is not theoretical. `syslog.pl` listens on UDP/514 for untrusted input, and the
UI is exposed over HTTP/HTTPS with a hand-rolled auth layer.

### 1.1 SQL injection in the search path **[security]** — ✅ fixed (see §0b)
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

### 1.2 Two `eval` sinks = remote code execution as root **[security]** — ✅ fixed (see §0d)
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

### 1.3 Password hashing is broken by construction **[security]** — ✅ fixed (bcrypt)
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

### 1.4 Password hashes leak through the JSON API **[security]** — ✅ fixed
`app/views/users/index.json.jbuilder` and `show.json.jbuilder` do
`json.extract! user, :id, :username, :password, ...`. Any caller that can reach
`/users.json` gets every salted hash. `SessionsController` also exposes full CRUD over
the `sessions` table (`session_params` permits `:user_id, :expiry`), i.e. an attacker can
mint a session row directly.

**Fix:** drop `:password` from every jbuilder (and never `select *` on `users`); make
`SessionsController` read-only (or delete it — sessions are an implementation detail of
`gatekeeper`). Add a request spec asserting `/users.json` has no `password` key.

### 1.5 Secrets committed to the repository **[security]** — **FIXED**

Four secrets were committed. All are now supplied at deploy time instead.

- `config/initializers/secret_token.rb` — hard-coded `secret_key_base`, deleted.
  Replaced by `config/secrets.yml` (the Rails 4.2 convention), which holds
  throwaway development/test values and reads production from
  `ENV["SECRET_KEY_BASE"]`.
- `config/database.yml` — production `rails`/`example` credentials replaced with
  `ENV["DAD_DB_*"]` interpolation. Verified to parse as ERB+YAML and to yield
  `nil` rather than a committed fallback when unset.
- `gather_eventlogs.rb` — deleted. It was a pasted shell transcript containing a
  live-looking domain account credential and internal hostnames, not code.
  Nothing referenced it.
- `db/seeds.rb` — the seeded admin hash (`Password1`) is gone. Seeding now reads
  `DAD_ADMIN_PASSWORD` and **refuses to run** if it is unset, rather than
  silently creating a well-known account on a public host.
- `provision.sh` — generates `SECRET_KEY_BASE`, a random DB password and a
  random admin password into `/etc/DAD/environment` (mode 600, created with
  `install -m 600` so it is never briefly world-readable), reuses them on
  re-provision, and passes them to Postgres, Apache/Passenger (`SetEnv`) and the
  CLI jobs. The completion banner prints the generated password instead of
  `Password1`.
- `config/initializers/require_secrets.rb` — new. Rails 4.2 only *warns* when
  `secret_key_base` is blank, so an unconfigured host would boot and sign
  cookies with no key. This raises instead.

**Still required, and outside this repo:** every credential above must be
**rotated**. They are in git history, which is not rewritten here — treat
`secret_key_base`, the `rails`/`example` DB password, and the `auditor` domain
account as compromised. If the repo has ever been public, scrub with
`git filter-repo`; note `.gitignore` never covered `config/database.yml`.

Brakeman: 7 → 6 warnings (the `Session Setting` finding on `secret_token.rb`
is gone; nothing new introduced).

### 1.6 Session handling **[security]** — ✅ fixed (SecureRandom)
`UsersController#generate_session_id` builds a 62-char-alphabet token from
`rand(10000) % field.count` — biased modulo reduction on `Kernel#rand`, and `rand` is not
a CSPRNG. Sessions are never rotated on login (the code does delete prior sessions, which
is good), the cookie is not `SameSite`, and `gatekeeper` re-issues the cookie on every
request. `cookies[:sessionID] = nil` on logoff does not reliably delete a cookie.

**Fix:** `SecureRandom.hex(32)`; `cookies[:sessionID] = { value: nil }` or
`cookies.delete(:sessionID)`; add `same_site: :lax`; consider just using Rails' built-in
`ActionDispatch::Session` (already configured in `config/initializers/session_store.rb`
and unused) instead of a parallel DB session store.

### 1.7 XSS in the event renderer **[security]** — **FIXED**

Event text and `System.name`/`System.address` are attacker-controlled: ingestion
tokenises the first field of every syslog line into `systems.address`
(`System.find_or_add`), and `display_name` falls back to `(address)`.

**The severity in the original write-up was wrong in both directions**, and
correcting it changed the fix:

- Rails 4.2 HTML-escapes `<%= %>` in `.js.erb` templates
  (`ErubiHandler.escape_whitelist` covers `text/plain` only). So the documented
  `search.js.erb` break-out via a `"` was *not* reachable — the quote arrived as
  `&quot;`.
- But HTML escaping does **not** escape backslashes. `?search_terms=\` emitted
  `value="\";` — a script `node --check` rejects as `SyntaxError`. A single
  backslash in a search query broke the page. That is the real, reproducible bug.
- `index.js.erb:29` interpolated raw event text into a JS string and was not in
  the original list at all. It was the worst site.

Fixes:

- `js_literal` (new helper) emits `to_json` + `ERB::Util.json_escape` as
  `html_safe`. `to_json` gives a real JS literal (backslashes, quotes, newlines);
  `json_escape` additionally encodes `< > &` so a value cannot close an inlined
  `<script>`. Ruby's `#inspect` — which `service_stats` and
  `system_service_stats` were returning — is not a JS escaper, so those now
  return arrays and the templates call `js_literal`.
- `_event_detail.html.erb`: hand-built href replaced with
  `search_events_path(search_terms:, timeframe:)`. Verified a token containing
  `"` or `&` is percent-encoded (`q%22onmouseover%3D…`, `r%26s%3D1`), so it can
  neither close the attribute nor inject a parameter.
- `timestamp_helper` now builds its span with `content_tag`, so it is
  `html_safe` by construction; the two `raw` call sites dropped.
- `index.js.erb` and `systems/show.js.erb`: every attacker-reachable value goes
  through `js_literal`. Numeric-only interpolations stay plain, deliberately —
  `hourly_stats` returns `NaN` when there are no samples and JSON has no `NaN`,
  so blanket `to_json` would silently turn it into `null`.
- The one remaining `raw` is `raw escape_javascript render …` in `search.js.erb`,
  the standard Rails idiom; `j` already escaped it and `raw` prevents
  double-escaping.

Tests: `test/helpers/js_literal_test.rb` pins the escaping contract (quote,
backslash, newline, `</script>`, `nil`, arrays, `html_safe`, JSON round-trip);
`test/controllers/xss_test.rb` renders the real search response end to end.

Brakeman: 7 → 4 warnings; the three resolved are exactly the XSS findings on
`_alerts.html.erb:13`, `_event_detail.html.erb:4` and `show.js.erb:9`. No new
findings. (The fourth remaining warning, `secret_token.rb`, is removed by the
secrets branch.)

**Not covered by CI:** `index.js.erb` and `systems/show.js.erb` call
Postgres-only `extract()`, and CI runs SQLite, so those templates are never
rendered by the suite. Verified by rendering them with the DB-dependent helpers
stubbed and syntax-checking the output with `node --check`. Closing that gap
means either a Postgres CI job or making `extract()` portable — worth deciding
before more view work.

### 1.8 Authorization is copy-pasted and inconsistent **[security]** — ✅ fixed
Seventeen controllers each redefined their own `authorized?` as a `before_filter`.
Verified against the running app:

- **`PreferencesController` had no override at all.** It inherited the
  `ApplicationController` default (any logged-in user), so a plain Viewer could
  `PUT /preferences/1` and change the live dashboard's page size — that value is
  stored in the shared `user_id = 0` Preference row and read by `Event.recent_events`.
  Confirmed by test: a Viewer changed it from 10 to 999.
- **`SessionsController` defined `authorized?` twice.** Ruby keeps the last
  definition, and that one redirected to `/homes`, which is not a route — so a
  non-admin hitting `/sessions` got a 302 to a dead path (observed: `302 →
  /homes`). It also passed a `Right` *record* to `has_right?`, which expects a
  name; it only worked because the Admin short-circuit made the lookup irrelevant.
- **Filter methods were public, so Rails advertised them as actions.**
  `RolesController.action_methods` contained `authorized?`, `ssl`, `gatekeeper`
  and `set_session_cookie` — on every controller. *Correction to the original
  write-up:* they were not actually reachable, because no route matches them
  (`GET /users/authorized` matches `GET /users/:id` and hits `#show`, and there
  is no `:controller/:action` catch-all). The exposure is latent rather than
  live — but it becomes live the moment anyone adds a catch-all route, and the
  same mechanism is what makes `PreferencesController`'s missing gate invisible.
- **`SearchesController` repeated the same guard six times** (five Detective,
  one Viewer), each with its own redirect.

**Fix applied:** one private `ApplicationController#authorized?` driven by three
frozen constants — `CONTROLLER_RIGHTS` (controller → any-one-of rights),
`ACTION_RIGHTS` (per-action overrides, e.g. saving a search needs Detective while
reading one needs Viewer) and `PUBLIC_ACTIONS` (the logon actions). All 17
overrides and all 6 inline guards deleted; `ssl`, `gatekeeper`,
`set_session_cookie` and `authorized?` made `private`, which removes them from
`action_methods`. The gate **fails closed**: a controller absent from the map is
denied rather than open, and a test asserts every controller is declared so the
omission surfaces in CI instead of as a silent 302 in production.

Net effect: −212 lines, and the whole policy is readable in one place.
`Pundit`/`CanCanCan` remain the better choice if the app grows beyond this
model; this keeps the existing roles/rights schema and adds no dependency.

---

## 2. Correctness bugs that are silently corrupting data

### 2.1 The dashboard drops *every* event when there are no exclusions **[correctness]** — ❌ misdiagnosed, real bug fixed (see §0g)
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

### 2.2 Timestamp parsing has a hard-coded 2014–2019 window **[correctness]** — ✅ fixed (see §0f)
`event.rb:196` — `elsif split_text[3].to_i > 2014 && split_text[3].to_i < 2020`. Every
event with a modern (2020+) year in that field falls through to the legacy
`"#{txttimestamp} #{@@current_year} GMT"` branch, which assumes the syslog day-of-year
format and stamps it with the *current* year. Depending on the log format this either
drops the event (parse raises, `rescue` → `return`) or files it under the wrong date.
This is the single most likely reason DAD appears to "lose" events today.

**Fix:** parse against a real format list (RFC3164, RFC5424, ISO-8601) with explicit
`DateTime.strptime` patterns, and treat unparseable timestamps as "now" plus a counter,
never as a silent `return`. Keep the raw line so the parse can be re-run later.

### 2.3 `Math` core module is reopened **[correctness]** — ✅ fixed (see §6.6)
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

### 2.4 Ingestion is not crash-safe and can double-insert **[correctness]** — **partly fixed (§6.2); double-insert still open, see §7.2**
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

### 2.5 `storeEvent` mangles data to avoid quoting bugs **[correctness]** — ✅ fixed (see §0b)
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

### 3.1 `events_words` has no indexes **[performance]** — ✅ fixed (see §0c)
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

### 3.3 Partitioning and retention **[performance] [operations]** — retention implemented (§6.4) but its caller is broken (§7.1); partitioning still open
`approximate_count` queries `pg_stat_user_tables where relname like 'events_p%'` — it
expects partitioned tables (`events_p…`) that no migration creates. (It now falls back
to `Event.count` when that sum comes back null, so an unpartitioned install reports a
real number instead of zero — see §0e. The partitioning and pruning gaps below remain.) Meanwhile
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

### 5.1 The `Event` model is 320 lines of class-variable global state **[maintainability]** — duplicate block deleted (§6.3); extraction still open
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

### 5.3 The test suite is red and misleading **[maintainability]** — ✅ fixed
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

### 5.4 `puts` as the only observability **[operations]** — ✅ fixed (see §6.1)
`Event.search`/`search_period`/`approximate_count` `puts` the generated SQL on every call
(`event.rb:47,105,120,163`) — in production that goes to the Passenger log, unbounded, and
leaks query internals. `prune_words` `puts` cache stats. `import_syslog.rb` rescues
`Exception` (not `StandardError`), prints the offending line, flushes, and `exit`s — one
bad line kills the collector.

**Fix:** use `Rails.logger` with a log level, and `ActiveSupport::Notifications` around
search/insert so timings land in the log with structured fields. Rescue `StandardError`
per line, count failures into a `Statistic`, and keep going.

---

### 5.5 Broken admin screens found while documenting every method **[correctness]** — partly obsolete, see §6.7

Documenting all 262 methods surfaced defects that only show up when you read each
action against the model it writes. Each is annotated in-place at the call site.

**`SessionsController#create` and `#update` raise on every real submission.**
`session_params` permits `:hash`, but the column is `session_hash`. ActiveRecord
raises `UnknownAttributeError` rather than ignoring the unknown key -- verified
with `rails runner`. So the admin "create session" and "edit session" forms are
dead; only index, show and destroy work. One-word fix, and it is the kind of bug
that survives because no test exercises those two routes.

**`JobsController#test` 500s as routed.** `set_job` runs only for
`[:show, :edit, :update, :destroy]`, so `@job` is nil when `test` reads
`@job.script`. The route exists (`get 'test'`), the action exists, and it cannot
work. Either add `:test` to the `before_action` list or delete the action.

**`PreferencesController` had no `authorized?` override.** ✅ fixed in §1.8 — it
inherited the `ApplicationController` default, so any logged-in user could change
the dashboard page size.

**`Users#destroy` does not revoke sessions.** Deleting an account leaves its
Session rows live, so the deleted user keeps their existing login until the
token expires (up to an hour, sliding on each request). `#do_logon` already shows
the correct pattern -- `Session.where(user_id:).each(&:destroy)`.

**`Users#update` re-hashes the password unconditionally.** An update that omits
the password field sets it to a hash of `nil`, silently locking the account out.
Guard on the param being present.

**Login answers differently for unknown users than for bad passwords.** Unknown
username redirects with no flash; a wrong password flashes "Logon Failed!". That
is an account-enumeration oracle, and it also means lockout state is only tracked
for accounts that exist.

**`CACHESIZE` is assigned twice** in `Event` (lines 31 and 57, both `100000`).
Harmless today because the values match, but it emits a redefine warning and
means a future edit to one is silently overridden by the other.

### 5.6 Project hygiene **[operations]**

**No LICENSE file.** The repo has no license, which for anything published on
GitHub means all rights are reserved by default and downstream use is legally
blocked. If DAD is meant to be open source, pick one and add it.

**The README is a 2014 status note, not documentation.** It describes work
planned for "January of 2015" and discusses insert rates as the headline metric.
It does not tell a new operator how to install, configure, or run the importer,
scheduler, or syslog collector. `README` and `README.rdoc` are near-duplicates of
each other; keep one.

**CI is green but shallow.** The workflow runs and passes in ~40s, which is the
14 unit tests plus 4 cucumber scenarios. That is not enough to catch the class of
bug in 5.5 -- two broken admin routes and a nil-instance action are all reachable
by a single request each. The highest-value next tests are request specs over the
CRUD routes, not more unit tests of model helpers.

## 6. Reassessment (2026-10-14, at `537e1fe`)

Everything in §1 and most of §2–5 has been fixed. Re-measuring the tree rather than
trusting this document's own checkmarks changed the ranking, so the rest of this
section supersedes the old "suggested sequence" table.

### 6.1 What is actually done

| Original item | Verified how |
|---|---|
| 1.1 SQL injection | no string-interpolated SQL left; Brakeman SQL Injection 11 → 0 |
| 1.2 `eval` sinks | `JobHandler::HANDLERS` closed registry; `DisplayRule` parses, never evals |
| 1.3 password hashing | `BCRYPT_COST = 12`, `store_password`/`check_password`, legacy rows upgraded on login |
| 1.4 hash leakage | no `password` key in any `app/views/**/*.jbuilder` |
| 1.5 committed secrets | §1.5 FIXED |
| 1.6 session ids | `SecureRandom.hex(32)` |
| 1.7 XSS, 1.8 authz | single `authorized?` gate, deny-by-default rights map |
| 2.1 exclusion filter | §0g (doc was misdiagnosed; real bug was a blank pattern) |
| 2.2 timestamp window | §0f |
| 2.3 `module Math` | moved to `Stats` (see §6.6) |
| 2.5 quote mangling | §0b |
| 3.1 search indexes | migration `20261013000002` |
| 5.3 red test suite | 107 runs / 0 failures; `positions.yml` fixture deleted |
| 5.4 `puts` in search path | no `puts` in `search`/`search_period`/`approximate_count` |

### 6.2 The biggest remaining win: make ingestion crash-safe (§2.4)

This is now the single highest-value change, and re-reading the code shows it is
worse than §2.4 described. Three separate ways to lose or duplicate data:

1. **Queues are cleared before the writes land.** `performPendingInserts`
   (`event.rb:512-557`) spawns a thread, then *unconditionally* resets
   `@@pendingEventValues` and `@@events_words` to empty arrays. Nothing joins that
   thread before the reset. If the thread raises, the batch is gone and the
   importer keeps going as if it succeeded.
2. **The two INSERTs are not in a transaction.** `events_words` is written first,
   then `events`. A crash between them leaves index rows pointing at events that
   do not exist -- searchable hits that 404.
3. **Files are renamed *after* processing.** `import_syslog.rb` moves each log to
   `../ProcessedLogs/` only once every line has been handed to `storeEvent`. Kill
   the process mid-file and the whole file is re-read on restart, colliding with
   the manually assigned `@@nextEventID` counter.

Compounding all three: **the threaded path is never executed by any test.**
`performPendingInserts` branches on `Rails.env.test?` and inserts inline during
tests, so the production code path -- the one with the threads, the missing joins
and the connection-pool pressure -- has zero coverage. `grep insertThreads test/`
returns nothing.

Also still present and still wrong: `@@nextEventID` is seeded from
`Event.all.count` (`event.rb:457`), a full table scan on a table the README
describes as holding hundreds of millions of rows.

**Fix, in order of value:** wrap each flush in one `ActiveRecord::Base.transaction`
and join the thread before clearing the queues; rename to a `.processing` name
*before* reading a file so a restart cannot re-process it; replace `Event.all.count`
with `Event.maximum(:id)`; then delete the `Rails.env.test?` branch so tests
exercise the same path production takes. Roughly 2 days, and it is the only item
here that prevents silent data loss.

### 6.3 Second win: the duplicated state block in `Event`

`event.rb:23-58` and again `59-75` declare the *same* 14 class variables and
constants twice. This is not cosmetic -- it is why every boot emits

```
warning: already initialized constant Event::CACHESIZE
```

and it is the visible symptom of the real problem: `Event` holds **102 `@@`
references** of mutable process-global state (word cache, system cache, service
cache, next-id counter, pending rows, thread list, throughput counters). That
state is why ingestion is hard to reason about, why the threaded path is
untestable, and why §5.1's "extract `EventIngestor`" is a prerequisite for
safely doing §6.2 rather than an independent cleanup.

**Cheapest useful step:** delete the duplicate block (minutes, removes the
warning, no behaviour change). **The real step:** move the ingest state into an
`EventIngestor` instance rather than class variables, which makes the transaction
and thread-join fixes in §6.2 straightforward instead of delicate.

### 6.4 Third win: retention (§3.3), because everything else is bounded by it

`purge_logs` in `import_syslog.rb` is an empty method with its body commented out,
yet the loop still prints `"Purged logs older than: ..."`. `ProcessedLogs`
therefore grows without limit on the same disk as the live queue. With no
partitioning and no row retention, `events` grows forever, which in turn makes
§6.2's full-table `Event.all.count` slower every month. This is a day of work and
it bounds the cost of several other items.

### 6.5 Worth doing, but not urgent

- **3.4 N+1s** are real and confirmed: `system_stats`/`service_stats` call
  `System.find`/`Service.find` once per group, and `System.with_events_within_hours`
  (`system.rb:31-38`) calls `System.find` per row on every dashboard poll. One
  `joins(...).pluck(...)` each.
- **2.6 residuals**, all still present: `Alert#criticality_name` compares
  `criticality == "4"` as a *string* while every sibling branch uses integers, so
  severity 4 renders as "Critical" instead of "Serious"; `Service` declares
  `has_many :servers` with no `Server` model; `routes.rb:71` still declares
  `resources :positions` for a model that does not exist; the empty
  `CreateIndicesOnEventsWords` migration is still in `db/migrate/`; `has_right?`
  still issues two `Right` queries per call.
- **5.6 hygiene**: still no LICENSE file.

### 6.6 §2.3 fixed, and it carried a user-visible bug

The four statistics helpers moved from a reopened core `Math` module to
`app/models/stats.rb`. The namespace collision was a latent hazard; the actual
user-facing defect was the empty-array case. On a fresh install the dashboard
rendered

```js
var stats = [NaN, NaN, NaN];
```

and `draw_gauge` computes `max = Math.floor(average + 3*standard_deviation)`, so
Highcharts received NaN axes. `Stats` now returns `0.0` for empty input, and the
dashboard renders `[0.0, 0.0, 0.0]`. Pinned by a new test that fails on the old
code with the literal NaN body.

### 6.7 Corrections to this document

- **§5.5 SessionsController claim is obsolete.** It says `#create` and `#update`
  raise on every submission. Those actions no longer exist and
  `resources :sessions, only: [:index, :show, :destroy]` does not route them. The
  `session_params` method that permits the nonexistent `:hash` attribute survives
  as dead code -- worth deleting, but it is not a live bug.
- **§5.5 `Users#update` claim needs care.** The action does call
  `store_password(params[:user][:password])` unconditionally, and `store_password`
  raises `ArgumentError` on nil, so an update omitting the field *should* 500.
  Probing it end-to-end returned 302 with the password unchanged, and the probe
  could not reach `GET /users` either (302) despite holding the Admin right -- so
  the request was denied before reaching the action. **The defect is unproven
  either way**; it needs a test that is actually authorized before anyone calls it
  fixed or broken.
- **§5.4 is fixed** and was left marked open.
- **§2.4's `Event.all.count` claim is confirmed still true** (`event.rb:457`).

### 6.8 Revised sequence

| Priority | Change | Effort | Payoff |
|---|---|---|---|
| 1 | §6.2 ingestion: transaction + join-before-clear + staged rename + `maximum(:id)` | 2 days | stops silent data loss and double-inserts |
| 2 | §6.3 delete duplicate state block; extract `EventIngestor` | 1 week | makes #1 safe to do and testable |
| 3 | §6.4 retention: implement `purge_logs`, re-enable, partition | 1 day | bounds every other cost |
| 4 | §3.4 dashboard N+1s | hours | faster dashboard polls |
| 5 | §2.6 residuals + dead code | hours | removes long-standing papercuts |
| 6 | Rails 5→7, one hop per PR | ongoing | removes the EOL liability |

If you only do two things: **§6.2 and §6.3**. They are the same problem viewed from
two sides, and they are the only items on the list that stop the tool from
quietly losing the data it exists to collect.

---

## 7. Reassessment (2026-10-14, at `104abd4`)

§6.2, §6.3 and §6.4 have all landed (PRs #12–#15, all merged; no PRs are open).
Re-measured: **3,470 lines** of app/lib Ruby across 18 controllers and 22 models,
plus 1,885 lines of tests. Suite is **135 runs / 390 assertions / 0 failures**,
Cucumber 4/4.

That green suite is the problem. **The importer does not run on master.** Two
regressions survived the merge, and neither is visible to CI.

### 7.1 🔴 Top priority: `import_syslog.rb` crashes on startup — `NameError`

`purge_logs` calls `LogRetention.purge`, but the file only requires
`./lib/log_queue.rb`. `lib/` is **not** in Rails' autoload paths, so the constant
does not resolve:

```
$ ruby import_syslog.rb
import_syslog.rb:59:in `purge_logs': uninitialized constant LogRetention (NameError)
```

Reproduced end-to-end against a migrated database. It is not a corner case: the
loop initialises `referenceTime = Time.now - 13.hours` specifically to *force* a
purge on the first iteration, so the process dies within seconds of every start.

**How it got in.** PR #13 added `require './lib/log_retention.rb'`; PR #15 added
`require './lib/log_queue.rb'` at the same line. The merge of #13 into #15
(`f376465`) kept one require and dropped the other while keeping both call sites.
A textual merge that resolved cleanly and produced a broken program.

**Why CI missed it.** Nothing in `test/` or `features/` ever loads
`import_syslog.rb` -- `grep -rn import_syslog test/ features/` returns nothing.
The retention tests exercise `LogRetention` directly, so they pass while its only
caller is dead. This is the same blind spot §6.2 flagged for the threaded path,
one level up: the entry point itself has no coverage.

**Fix (minutes):** add the missing `require`. **Then prevent a recurrence:**
require the script in a test. It cannot be `require`d as-is because of the
top-level `while true` loop, so guard the loop with `if __FILE__ == $0` -- that
also makes the whole importer testable, which it currently is not.

Also from the same merge: `PROCESSED_DIR` and `PROCESSED_LOGS` are two constants
for the same `'../ProcessedLogs'` path, used by different halves of the file.
Collapse to one.

### 7.2 🔴 Crash-then-reclaim still duplicates rows

§6.2's stated goal was to stop "silent data loss **and double-inserts**". The
data-loss half is fixed; the double-insert half is not. Reclaim re-reads a
`.processing` file **from the beginning**, but rows committed before the crash are
already in the database, and `storeEvent` has no dedup.

Reproduced: 6-line file, batch size 2, crash before line 4.

```
RUN 1: stores lines 1-3; batches of 2 commit  -> ids 1,2 persisted
RUN 2: reclaims sample.log.processing, re-reads all 6 lines
FINAL: count=4
  1 ... line number 1
  2 ... line number 2
  3 ... line number 1      <- duplicate
  4 ... line number 2      <- duplicate
DUPLICATE LINE TEXTS: 2
```

The `.processing` rename makes a crash *visible*, which is real progress, but it
does not make reprocessing *safe*. The claim in `log_queue.rb` that re-reading
from the top is "the correct recovery" is only true for rows that were never
committed -- and there is no mechanism that knows which those were.

**Options, in order of cost:**
1. **Idempotent re-read.** Persist a byte offset per in-flight file and resume
   there. Cheapest correct fix; needs the offset written at each flush, not each
   line.
2. **Natural key + `ON CONFLICT DO NOTHING`** on `(system_id, generated, hunks)`.
   Needs a unique index over a `text` column on a table sized in the hundreds of
   millions -- expensive, and it changes semantics for legitimate repeats.
3. **Accept duplicates and document them.** Defensible for a log search tool, but
   it must be a written decision, not an accident, and it inflates every count on
   the dashboard.

Recommend (1). Roughly a day, and it is the only remaining item that corrupts data.

### 7.3 Two probe results worth recording, one of which corrects an earlier claim

- **The `SQLite3::BusyException` in §0b's footnote is not fixed.** It reproduces
  in the threaded development path: a `Statistic` write from the main thread
  collides with the in-flight insert thread. It does not affect the PostgreSQL
  deployment, but it does mean the SQLite dev database cannot exercise the
  threaded path at more than one batch in flight -- which is exactly why the new
  ingest tests run one batch per case and the multi-batch concurrent case is
  **still untested**.
- **Correction to a claim made while writing §6.2:** an earlier probe appeared to
  show reclaim producing no duplicates. It was wrong -- the probe called
  `load 'db/schema.rb'` on restart, and `schema.rb` uses `force: :cascade`, so it
  silently dropped the rows run 1 had committed. The result was an artifact of the
  harness. §7.2 is the corrected measurement.

### 7.4 Still open from §6

| Item | Status at `104abd4` |
|---|---|
| §6.2 ingestion crash-safety | Partially done. Transactions, thread joins, staged rename, `maximum(:id)` all landed. **Double-insert not fixed (§7.2).** |
| §6.3 duplicate state block | Duplicate block deleted; `EventIngestor` extraction **not** done. `event.rb` is 626 lines with **80 `@@` references**. |
| §6.4 retention | Implemented, but the caller is broken (§7.1). Partitioning still absent. |
| §6.5 N+1s | Unchanged: `application_helper.rb:107,122` call `System.find`/`Service.find` per group; `system.rb:35` calls `System.find` per row on every dashboard poll. |
| §6.5 residuals | All still present: `alert.rb:28` compares `criticality == "4"` as a string; `service.rb:8` `has_many :servers` with no `Server` model; `routes.rb:71` `resources :positions`; empty `CreateIndicesOnEventsWords` migration still in `db/migrate/`; `has_right?` still issues two `Right` queries per call. |
| §6.5 hygiene | Still no LICENSE file. |
| §1.5 secret rotation | Committed `secret_key_base` moved to ENV, but **never rotated** -- it is still compromised in history. |
| §4.1 Rails upgrade | Not started; CI security job still `continue-on-error: true` (lines 56, 60). |
| §2.4 test-env branch | `Rails.env.test?` branch at `event.rb:552` still present, so tests still do not run the production insert path in-process. |

### 7.5 Revised sequence

| Priority | Change | Effort | Payoff |
|---|---|---|---|
| 1 | §7.1 missing `require` + `__FILE__ == $0` guard + a test that loads the importer | hours | the importer runs at all; closes the blind spot that hid this |
| 2 | §7.2 make reclaim idempotent (byte offset) | 1 day | stops the last data-corrupting defect |
| 3 | §6.3 extract `EventIngestor`; delete the `Rails.env.test?` branch | 1 week | makes #2 and all future ingest work testable in-process |
| 4 | §6.5 N+1s + residuals + rotate the §1.5 secret | hours | papercuts, one of which is a live credential |
| 5 | §3.3 partitioning; §4.1 Rails 5→7 | ongoing | bounds growth, removes the EOL liability |

**The lesson to carry forward:** the suite tests units, not the entry point. A
green build with a dead importer is exactly what a test suite that never loads
`import_syslog.rb` will produce. Fix #1 is cheap, but the `__FILE__ == $0` guard
plus one smoke test is the part that stops it happening again.

---

*This review was produced by an AI agent (OpenHands) on behalf of the user.*

---

## 8. Reassessment (2026-10-14, at `104abd4` + §7.5 items 1, 2, 4)

Items 1, 2 and 4 from §7.5 are implemented and pushed. Item 3 turned out to rest
on a false premise; see §8.3.

### 8.1 ✅ §7.1 -- the importer was dead on arrival (branch `fix-import-syslog`)

`purge_logs` called `LogRetention.purge` with no `require './lib/log_retention.rb'`,
so every run died at startup with `NameError: uninitialized constant LogRetention`.
The suite was green throughout: nothing loaded `import_syslog.rb`.

Also on that branch: duplicate `PROCESSED_DIR` / `PROCESSED_LOGS` constants
collapsed into one, and a `__FILE__ == $PROGRAM_NAME` guard makes the script
loadable, which is what makes the new tests possible at all.

### 8.2 ✅ §7.2 -- reclaim is now idempotent (branch `fix-reclaim-idempotent`)

Byte-offset checkpoints. `LogQueue` keeps a `<name>.processing.offset` sidecar;
`Event` releases it per batch, only ever for the head of the queue.

Three findings that only appeared once crash-then-reclaim was actually driven
end to end:

1. **The checkpoint has to be written by the writer thread.** If only the main
   thread records it, a process killed while a batch is in flight commits rows
   it never recorded, and the next run re-inserts them. Measured: 6-line file,
   died mid-batch, lines 1 and 2 stored twice.
2. **The checkpoint must derive from staged rows, not a mutable global.** An
   early version tracked a position updated by the reader, which ran ahead of
   what had been staged. Measured: line 2 went *missing* -- data loss, strictly
   worse than the duplication it was meant to fix. `storeEvent` now takes the
   line's byte offset, so a batch's checkpoint is the offset of its last row.
3. **A latent double-insert, independent of reclaim.** `performPendingInserts`
   cleared `@@pendingEventValues` / `@@events_words` *after*
   `Statistic.logEventsPerSecond`, which writes to the same database. When that
   raised, rows already handed to a writer thread were still staged, and the
   next flush inserted them again under the same explicit ids:
   `UNIQUE constraint failed: events.id`. The queues are now cleared as soon as
   the statements are built.

`test/import_syslog_crash_test.rb` drives real subprocesses with `exit!`, so the
crash bypasses every rescue and `at_exit`. Negative control: master's
`Event` + `LogQueue` fail 2 of 3; the fix passes 3/3.

The guarantee is at-least-once, bounded to one batch. A crash with a batch in
flight may re-read it; it may not lose a line, and it may not duplicate more
than one batch.

### 8.3 ❌ §7.5 item 3 -- "delete the `Rails.env.test?` branch" cannot be done

The branch exists because of a hard constraint, not laziness. Measured directly:
forcing the threaded path under transactional fixtures on SQLite fails
immediately --

```
ActiveRecord::StatementInvalid: SQLite3::BusyException: database is locked:
  INSERT INTO events_words (event_id, word_id, generated) VALUES ...
```

The test transaction holds the only SQLite writer; a second connection cannot
write at all. So the branch cannot be deleted while the suite runs on SQLite.

Revised options, in order of value per unit of risk:

| Option | What it buys | Cost |
|---|---|---|
| **A. Test the threaded path in subprocesses** | Real coverage of production code, no production change. Already proven: `event_ingest_flush_test.rb` and `import_syslog_crash_test.rb` both do this. | hours |
| **B. Extract `EventIngestor` as a stateful object** | Kills the 80 `@@` references and the `class_variable_get` poking in `event_state_test.rb:42-49` and `timestamp_parsing_test.rb:107`. Does **not** remove the env branch. | ~1 week, touches the hot path |
| **C. Move the test DB to Postgres** | The only way to actually delete the branch and test in-process. | large; changes CI and every dev setup |

Recommendation: **A now, B later, C only alongside the §4.1 Rails upgrade.**
A is nearly free because the subprocess harness already exists.

### 8.4 ✅ §6.5 -- N+1s and residuals (branch `fix-n1-and-residuals`)

- `system_stats` / `service_stats`: one `find` per group -> one grouped count
  plus a single `WHERE id IN (...)`.
- `System.with_events_within_hours`: same, and it runs on every dashboard poll.
  Verified at 2 queries regardless of host count.
- `system_stats` keyed results by `display_name`, so two hosts sharing a name
  collapsed into one entry and one count silently vanished from the chart.
  Keyed by id.
- `User#has_right?` ran two `Right.where(...).first` queries per call, and
  `authorized?` calls it once per required right per request. Now one rights
  load per user.
- `Alert#criticality_name` compared the integer column against the string `"4"`,
  so a Serious alert was labelled Critical.
- Dead code removed: `Service has_many :servers` (no `Server` model, no
  callers), `resources :positions` (no model, controller, view or table), and
  `CreateIndicesOnEventsWords`, which was entirely commented out.
- Committed development/test `secret_key_base` values rotated. Production
  already reads `SECRET_KEY_BASE` from the environment, so no live credential
  changed; the old values remain burned in history.

### 8.5 Suite state

| | Result |
|---|---|
| `rake test` | 157 runs, 457 assertions, **0 failures, 0 errors** |
| `cucumber` | 4 scenarios, 4 passed |
| `brakeman` | 3 warnings (unchanged baseline) |

One intermittent `SQLite3::BusyException` remains in the threaded-path tests
(§7.3). It predates this work and is the same single-writer constraint as §8.3;
it is not caused by any change here.

### 8.6 Revised sequence from here

| Priority | Change | Effort |
|---|---|---|
| 1 | Merge §8.1, §8.2, §8.4 (three stacked branches) | -- |
| 2 | §8.3 option A: more subprocess coverage of the threaded path | hours |
| 3 | §3.3 partitioning; §4.1 Rails 5 -> 7 | ongoing |
| 4 | §8.3 option B: `EventIngestor` extraction, if the `@@` state still hurts | ~1 week |
| 5 | §8.3 option C: Postgres test DB, folded into the Rails upgrade | large |
