# DAD — Open Recommendations

Scanned at `b6adf25` (2026-10-14); §2.1 re-verified and closed at the branch
adding `users_admin_test.rb`. PRs #1–#23 all merged.

**This document lists only work that is still outstanding.** Everything marked
closed is verified against the current tree, not against what a PR claimed. The
full review history — the original findings, the misdiagnoses, and the reasoning
behind each fix — lives in the git history of this file (see the appendix for
where to find it).

Every item below was re-checked by reading the code at `b6adf25`. Where a claim
from an earlier revision turned out to be stale, it is corrected here rather
than carried forward.

## Status snapshot

| Area | State |
|---|---|
| SQL injection, `eval` sinks, password hashing, hash leakage, XSS, authorization | Closed |
| Secrets in the working tree | Closed — **but a production key is still in git history (§1.1)** |
| Ingestion crash-safety and idempotency | Closed, at-least-once (§2.2) |
| Search indexing, dashboard SQL portability, timestamp parsing | Closed |
| Test suite | Green: 194 runs / 542 assertions, 4 cucumber scenarios |
| Admin screens (sessions, users, jobs) | Closed — now covered by request tests (§2.1) |
| Poison line / observability | **Open — was mis-marked as fixed (§5.3)** |
| Rails upgrade | **4.2 → 5.2 → 6.1 → 7.1 landed**; 7.1 → 8.1 open (§5.2) |
| Rails 7.1 EOL, CI security gates | Open (§5.2, §1.2) |
| Partitioning, full-text search | Open (§3) |

---

## 1. Security

### 1.1 🔴 A production `secret_key_base` is still recoverable from git history **[security]**

This is the one genuinely open security item, and it had been recorded as closed.

`config/initializers/secret_token.rb` at commit `de2043a` ("Converting to a Rails
4 application", 2015-01-07) hardcoded:

```ruby
Events::Application.config.secret_key_base = '109a47e9ccc231214dbec0dac1fbd5c0...'
```

That value is a **production** key, distinct from the development and test values
in `config/secrets.yml`. It is gone from the working tree but still present in
every clone's history.

**Why the earlier "rotated" note was insufficient.** PR #18 rotated the
development and test values in `config/secrets.yml`. Those were never secrets —
they sign cookies on a developer's own machine. The production key above was not
touched, because it lives in a different file that no longer exists.

**Impact.** Anyone who has ever cloned the repo can recover the key and forge
signed cookies — which, with this app's hand-rolled `cookies[:sessionID]` scheme,
means impersonating any user including Admin — for as long as any deployed
instance still uses that key.

**Fix, in order:**
1. Confirm whether any live deployment still uses it. If so, set a new
   `SECRET_KEY_BASE` there (the env-var path already exists via
   `config/initializers/require_secrets.rb`, which fails closed in production).
2. Decide whether history needs rewriting. `git filter-repo` over a shared
   history is disruptive and does not reach existing clones, so it only helps if
   the repo is private and the key is being retired anyway. Rotating the key is
   the real fix; rewriting history is hygiene.
3. Add a secret-scanning gate so this cannot recur — `gitleaks` or
   `detect-secrets` as a CI step, and as a pre-commit hook.

### 1.2 CI security gates are advisory, not blocking **[security] [operations]**

`.github/workflows/ci.yml` lines 56 and 60 run `bundle-audit` and `brakeman` with
`continue-on-error: true`. Both are currently informational, so a new vulnerable
gem or a new injection sink merges green.

After the 4.2 → 5.2 step, Brakeman reports **2 warnings** (down from 3) and
bundle-audit advisories drop from **88 to 46** — the Rails/rack/actionpack
framework CVEs are gone; what remains is mostly transitive (`rdoc`, `sqlite3`).
Measured again after the 6.1 → 7.1 step: Brakeman is unchanged at **1 warning**
(one high-confidence finding, pre-existing), and bundle-audit advisories fall from
**40 to 25**. The `json 1.8.6`, `rdoc` and 17 `nokogiri` advisories are gone; what
remains is 10 × `sqlite3` (the dev/test-only gem, capped at 1.7.3 by the
`< 2.0` ceiling — see §5.2), 6 × `activestorage` (an engine this app does not use
at all), and `httparty`/`jquery-rails`/`mail`/`actionview`.

**Fix:** split the job. Make **brakeman blocking now** (the 2 warnings are
pre-existing and can be baselined with an ignore file, so blocking does not stall
PRs); keep bundle-audit advisory until Rails is on a supported line, since the
remaining advisories still need dependency work rather than app changes.

---

## 2. Correctness

### 2.1 ✅ Closed — admin screens were broken and untested **[correctness]**

Closed by PR #23, which adds `test/controllers/users_admin_test.rb` and
`sessions_admin_test.rb`. **Three of the four defects listed in the previous
revision of this document were described incorrectly**, which is worth recording
because the misdescriptions changed what the right fix was:

| Claimed | Actual |
|---|---|
| `Sessions#create`/`#update` raise `UnknownAttributeError` on `:hash` | **Not a live defect.** Those actions are not routed (`resources :sessions, only: [:index, :show, :destroy]`) and do not exist; `session_params` was never called. The real defect was in the *routed* screens: `index.html.erb` and `show.html.erb` called `edit_session_path`/`new_session_path`, which no longer exist, so **both 500'd** on `ActionView::Template::Error`. |
| `Users#destroy` leaves sessions live, so a deleted account **keeps access indefinitely** | Sessions were indeed left live, but the consequence is the opposite: `gatekeeper` resolves a cookie via `User.find(session.user_id)`, so the orphaned row made every request carrying that cookie raise `ActiveRecord::RecordNotFound`. A deleted account did not stay logged in — it produced a 500 until the cookie expired. |
| `Users#update` with no password sets "a hash of `nil`" | `store_password` raises `ArgumentError` on `nil` ("password is too long"), so that path was a **500**, not a silent lockout. The real lockout comes from the *empty string*: the edit form renders `password` blank, submitting it unchanged hashed `""`, so the original password stopped working and `check_password('')` began returning true. |

Two further defects in the same code, found while probing and fixed together:

- **Plaintext passwords were persisted.** `user_params` permits `:password`, so
  `update` wrote the raw value to the column *before* `store_password` ran. When
  `store_password` raised (any password over 72 bytes), the plaintext stayed
  saved. Verified: `select password from users` returned the submitted string.
- **`create` minted accounts with an empty password.** `store_password('')`
  succeeds, so posting a blank password created an account that
  `check_password('')` accepts.

Also fixed in the same pass:

- `jobs#test` 500'd exactly as described (`@job` nil). It had **no view at all** —
  `app/views/jobs/test.html.erb` has never existed in the repo's history — so
  fixing `set_job` would only have moved the failure to a missing template. The
  action duplicated what `jobs#show` already renders, so the action and its route
  are deleted.
- The Sessions JSON views extracted `:hash`, which is `Object#hash` — a random
  integer, not the token. Harmless by accident. Both now omit `session_hash`
  deliberately: it is the sole bearer credential `gatekeeper` accepts, so
  exposing it to anyone with the Sessions right would be a session-hijack path.
  The HTML views show an 8-character prefix for correlation.
- Dead code removed: `session_params`, `sessions/{_form,new,edit}.html.erb`
  (unroutable), and the `jobs` `test` member route.

**The lesson holds.** Every one of these survived because no request ever touched
the route. The new tests are request-level, and 12 of the 18 fail against the
pre-fix tree.

### 2.2 Ingestion is at-least-once, not exactly-once **[correctness]** — accepted, document it

PR #17 made crash-then-reclaim idempotent **up to one batch**: a crash with a
batch in flight may re-read that batch, so a small number of rows can be
duplicated. It cannot lose a line, and it cannot duplicate more than one batch.

This is a deliberate trade-off, not a bug, and the tests pin it. It is listed
here because it is a property an operator needs to know: **duplicate events are
possible after a crash**, so anything counting events (the dashboards, alert
thresholds, `Statistic` rates) is approximate across a crash boundary.

If exactly-once is ever required, the options are a uniqueness constraint on a
line fingerprint (costly: needs a hash column and an index over a large table) or
`INSERT ... ON CONFLICT DO NOTHING` keyed on that fingerprint. Neither is worth
it unless duplicates are actually causing problems.

---

## 3. Performance

### 3.1 ✅ Closed — the statistics helpers re-ran the same query **[performance]**

`ApplicationHelper` had four methods calling `statistics_by_hour(0, since)` and
reducing the same rows differently; `System#hourly_stats` and
`System#events_per_hour` did the same over `System.hourly_counts`. Each reduction
was its own round trip for identical rows, on a page that re-renders itself every
60 seconds.

Fixed by fetching the bucketed rows once (`ApplicationHelper#hourly_buckets`,
`System.hourly_buckets`) and reducing them in Ruby through a new `BucketStats`
module (`series`, `summary`). A module rather than view helpers because
the models build the same series — previously `System` reached into
`ApplicationHelper.chart_label` directly.

Measured on a real `events.js` render: **5 grouped queries → 4**. The fifth was
`hourly_stats(1.days.ago)` and `hourly_stats(1.day.ago)` on consecutive template
lines — the same series fetched twice, so the template now reuses `stats`.

Two judgement calls worth knowing about:

- **`hourly_average` was deleted, not refactored.** It had no call sites anywhere
  in the repo.
- **`System#hourly_stats` deliberately still issues its own query** rather than
  deriving from the 7-day series `#events_per_hour` already fetches on the same
  page. The SQL filters on the exact `since` instant, so the bucket straddling it
  is *partial*; that cannot be recovered from already-bucketed rows, and narrowing
  pre-bucketed data would silently change the baseline the anomaly gauges compare
  against. Pinned by `test_system_hourly_stats_counts_only_events_after_the_exact_instant`.
- `daily_insert_average` keeps averaging the `sum` aggregate. The type_id 1 samples
  are already per-second rates, so `avg` is arguably correct — but switching it
  moves a number on the dashboard, which is a behaviour change, not a refactor.

*The previous revision's "correction" here was wrong.* It stated
`system_service_stats` no longer exists. It does — `app/helpers/systems_helper.rb`,
called from `systems/show.js.erb:21` — and it was a live N+1 doing one `Service.find`
per distinct service. Unbounded (no time window), so on a long-lived install that is
one query per service the host has ever reported. Fixed to the batched-lookup pattern
PR #18 used for `system_stats`/`service_stats`: **4 finds → 0**, two queries total.

New coverage in `test/helpers/statistics_query_test.rb` (14 tests) asserts both the
round-trip counts and that the numbers did not move. Negative control: 4 of the 14
fail against the pre-fix tree.

### 3.2 No partitioning or retention enforcement at the database level **[performance] [operations]**

`LogRetention` (§6.4 in the old numbering) trims processed *log files*, but the
`events` and `events_words` tables grow without bound. There is no partitioning
and no row-level purge path.

This is the item that bounds everything else: index size, search latency, and
backup time all degrade with it, and no query-level optimisation stays effective
under unbounded growth.

**Fix:** monthly range partitioning on `generated`, with retention expressed as
dropping old partitions rather than deleting rows. Note this is Postgres-specific
and the app currently runs SQLite in dev/test — so it should land alongside the
Rails/Postgres work in §5.2, not before it, or dev/test will diverge further.

### 3.3 Postgres-native full-text search **[performance]**

Search is still `LIKE '%term%'` over `words.text` joined through `events_words`.
PR #2 added the missing indexes, which made it acceptable rather than pathological,
but `LIKE '%…%'` cannot use a plain index for the leading wildcard.

Longer term, `tsvector`/`GIN` is the better shape. Listed as a lower priority than
§3.1 and §3.2 because the indexes already landed and the current behaviour is
correct — this is a scaling improvement, not a fix.

---

## 4. Maintainability

### 4.1 `Event` is 715 lines with 101 class-variable references **[maintainability]**

`app/models/event.rb` has grown since the last review (626 lines / 80 `@@`
references → 715 / 101). Ingestion state — pending rows, next id, word/system/
service caches, checkpoint bookkeeping, insert threads — is process-global class
state.

The concrete cost is testability. `test/models/event_state_test.rb:42-49` and
`timestamp_parsing_test.rb:107` reach into internals with
`class_variable_get`, which means the tests are coupled to the storage mechanism
rather than the behaviour, and any refactor of that state breaks them.

**Important correction to the previous plan.** The earlier recommendation was to
extract an `EventIngestor` *and delete the `Rails.env.test?` branch* in
`performPendingInserts`. The second half is not achievable, and was measured:

```
ActiveRecord::StatementInvalid: SQLite3::BusyException: database is locked:
  INSERT INTO events_words (event_id, word_id, generated) VALUES ...
```

The test transaction holds the only SQLite writer, so a second connection cannot
write at all. The branch is load-bearing, not lazy. Extracting `EventIngestor`
would clean up the `@@` state but would **not** remove the branch, so it does not
deliver the payoff the item promised.

Revised options, by value per unit of risk:

| Option | What it buys | Cost |
|---|---|---|
| **A. More subprocess coverage of the threaded path** | Real coverage of production code, no production change. Already proven by `event_ingest_flush_test.rb` and `import_syslog_crash_test.rb` | hours |
| **B. Extract `EventIngestor`** | Kills the `@@` state and the `class_variable_get` coupling. Does **not** remove the env branch | ~1 week, touches the hot path |
| **C. Postgres test database** | The only way to delete the branch and test in-process | large; changes CI and every dev setup |

**Recommendation: A now, B only if the `@@` state keeps causing bugs, C folded
into §5.2.** A is nearly free because the subprocess harness already exists.

### 4.2 Dead and duplicated code **[maintainability]**

Verified still present:

- `Event.search` and `Event.search_period` (`event.rb:297`, `:305`) are the same
  query with a different time bound. Merge into one method taking a range.
- `System#hourly_stats` / `#events_per_hour` and the four `ApplicationHelper`
  statistics methods — see §3.1, same root cause.
- `export_logs.rb` at the repo root.
- `syslog.pl`'s unused `$DEBUG` / `$Filename` globals.
- 14 `*.js.coffee` and 15 `*.css.scss` scaffold stubs from `scaffold :model`.

Verified already gone (do not go looking for these): `Event.search2` and
`iterativeSQLBuilder`, `gather_eventlogs.rb`, the duplicated `authorized?`
blocks across 15 controllers, `Service has_many :servers`, `resources :positions`
and its fixture, and the empty `CreateIndicesOnEventsWords` migration.

### 4.3 The suite is green but shallow on the routes that broke **[maintainability]**

194 runs / 534 assertions across 44 test files, plus 4 cucumber scenarios.

The admin CRUD request specs called for in the previous revision now exist
(`users_admin_test.rb`, `sessions_admin_test.rb`), which is what closed §2.1.
Remaining gaps: no coverage of the `roles`/`role_add`/`role_remove` privilege
escalation path, and no coverage of `alerts` acknowledgement.

One known flake: an intermittent `SQLite3::BusyException` in the threaded-path
tests. It is the same single-writer constraint as §4.1 and predates all recent
work. Confirmed by rerun — a failing run passes immediately afterwards.

---

## 5. Operations

### 5.1 `provision.sh` is not idempotent and the services do not survive reboot **[operations]**

Verified at `b6adf25`:

- Line 71 (and 84, 93): `sudo cat << EOF > /etc/apache2/...` — `sudo` applies to
  `cat`, not to the shell redirection. It only works because the script already
  runs as root, and silently does the wrong thing under `sudo -u`.
- Line 124: `ln -s .../ssl.conf .../mods-enabled/ssl.conf` fails on re-run.
  Should be `a2enmod ssl` (which the script already uses correctly at line 67).
- `perl syslog.pl &` and `ruby import_syslog.rb &` are backgrounded. They die on
  VM reboot with no restart, no log rotation, and no health check.

**Fix:** ship systemd units (`dad-syslog`, `dad-importer`, `dad-scheduler`) with
`Restart=always`, make `provision.sh` a thin wrapper around them, and use
`install -m 0644` with a heredoc instead of `sudo cat >`.

### 5.2 Rails is end-of-life — what a Rails 8 upgrade actually requires **[operations]**

`Gemfile` pins `rails '~> 7.1.0'` (resolves 7.1.6). Steps 1 (→ 5.2), 2 (→ 6.1)
and 3 (→ 7.1) of the sequence at the end of this section have landed; the plan
below is kept in full because the remaining steps (7.2 → 8.1) still depend on it.
7.1 has been EOL since October 2024 and has open CVEs with no fix available,
which is why bundle-audit stays non-blocking (§1.2). Ruby is pinned to 3.3.8 in
CI — supported, and already past the 7.2/8.1 floors (3.1 / 3.2), so the Ruby jump
that used to gate step 4 is done.

This is the dependency that gates several other items: Postgres partitioning
(§3.2) and a Postgres test database (§4.1 option C) both become tractable during
a Rails upgrade, and the CI security gates can only be made blocking afterwards.

**Baseline at the start of this workstream.** Rails 4.2.11.3 · Ruby 2.7.8 ·
Bundler 1.17.3 · rack 1.6.13 · sprockets 2.12.5 · SQLite in dev/test, Postgres in
prod (`pg 0.21.0`). **Current baseline after steps 1–3:** Rails 7.1.6 ·
Ruby 3.3.8 · Bundler 2.6.7 · rack 2.2 · sprockets 3.7.5 · jbuilder 2.13 ·
nokogiri 1.19 · pg 1.7 · sqlite3 1.7.3 · json 2.19 (pinned off the 3.x default
gem) · minitest 5.27 (pinned off 6.x).
3,680 LOC of Ruby in `app`/`lib`, 1,735 LOC across 90 views (34 of them
jbuilder), 2,923 LOC of tests, 29 migrations, 22 models, 19 controllers.

**4.2 → 8.0 is eight majors.** The findings below are separated by *where they
break*, because that determines the order of work. Claims marked **verified** were
run against ActiveRecord 7.0.8 on this machine; the rest are from release notes.

#### The constraint that sets the whole shape: Ruby and Rails cannot move independently

Rails 8 requires Ruby ≥ 3.2.0 — **verified**: `gem install rails -v 8.0.0` refuses
outright on 2.7.8. But Rails 4.2 cannot run on Ruby 3 either (the `bigdecimal
~> 1.4.4` pin exists only because bigdecimal 2.x removed `BigDecimal.new`, which
ActiveSupport 4.2 calls during boot — see `Gemfile:11`).

So Rails 4.2 is hard-capped at Ruby 2.7, and the two have to be walked up in
lockstep. The useful part: **Rails 7.1 is the last release that allows Ruby 2.7**
— **verified** from the gemspecs: 7.0.8 and 7.1.5 are both `>= 2.7.0`, 7.2.2 is
`>= 3.1.0`, 8.0.0 is `>= 3.2.0`. That meant 4.2 → 5 → 6 → 7.1 could all be done
*without* touching Ruby, with the Ruby jump landing once, at 7.2.

**That plan is now overtaken.** Step 3 jumped Ruby to 3.3.8 at the same time as
Rails 7.1 rather than staying on 2.7, because staying on 2.7 turned out to be the
expensive option: nokogiri and sqlite3 both dropped Ruby 2.7 support, and Ruby 3.3
ships `json` 3.x as a default gem, which breaks ActiveSupport 7.1 (see the landed
notes below). 3.3.8 is already above the 7.2 and 8.1 floors, so **step 4 (→ 7.2)
is now a pure Rails change with no Ruby work in it.**

#### Hard failures, fixable *now* on 4.2 (do these first — they are free)

1. **`exec_query` bind format.** Six call sites pass Rails-4 style pairs:
   `[[nil, value]]` (`event.rb:533-534`, `system.rb:47,82,99`,
   `application_helper.rb:72`). On AR 7.0.8 that raises **`TypeError: can't cast
   Array`** — **verified**. It is not a deprecation; it is a hard failure.

   The fix is `sanitize_sql_array` + `exec_query(sql)` with no binds argument.
   **Verified working on both 4.2.11.3 and 7.0.8**, so it can be merged today and
   removes a whole class of breakage from every later step. (Note
   `sanitize_sql_array` is `protected` on 4.2 and public from 5.0, so call it from
   inside the model, not as `ActiveRecord::Base.sanitize_sql_array`.)

2. **`before_filter` → `before_action`** (`application_controller.rb:53`).
   `before_action` already exists on 4.2 — **verified** — so this is a one-line
   back-port.

3. **Dead weight to delete now**, all of it reducing later conflicts:
   `rspec-rails ~> 3.5` (there is no `spec/` directory and zero rspec usage),
   `sdoc`, and the `mail` gem plus the `config.action_mailer` lines in all three
   environments — **the app has no mailers at all**, so that config is vestigial.
   `scheduler.rb:4` `puts $SAFE`: deprecated on 2.7, an ordinary global (nil) in
   Ruby 3.x, so it is noise rather than a crash — delete it.

4. **The `$_models` boot hack is the biggest structural risk** and it is worth
   fixing before any upgrade starts. `config/application.rb:39-43` eagerly
   `require`s every file under `app/models` inside a **bare `rescue`**, then
   snapshots `ActiveRecord::Base.subclasses` into a global that the nav bar
   iterates (`layouts/application.html.erb:12`). Two separate problems:
   - Zeitwerk (default from Rails 6) autoloads *lazily*, so a boot-time
     `subclasses` snapshot is **empty** — **verified**: `ActiveRecord::Base.subclasses`
     returns `[]` before anything is referenced. The nav bar would silently render
     nothing rather than fail.
   - The bare `rescue` already swallows model load failures today, so a broken
     model just vanishes from the nav bar. This is the same "nothing exercises the
     entry points" pattern as §4.3.

   Replace it with an explicit, ordered list of the models the nav bar shows.
   Good news: **the file naming is already Zeitwerk-clean** — all 56 files under
   `app/` map filename → constant correctly, and nested constants
   (`DisplayRule::Invalid`, `JobHandler::UnknownHandler`) are legal. Zeitwerk will
   not reject this codebase; only the boot-time snapshot blocks it.

#### Breaks that cannot be back-ported (they land at a specific step)

5. **Bare `ActiveRecord::Migration`** — all 29 migrations. On 7.0.8 this raises
   **"Directly inheriting from ActiveRecord::Migration is not supported"** —
   **verified**. Needs `ActiveRecord::Migration[5.0]`-style brackets, but
   `ActiveRecord::Migration[4.2]` **does not exist on 4.2** (**verified**:
   `NoMethodError`), so this cannot be prepared in advance — it happens at the 5.0
   step. `db/schema.rb` needs the same treatment (`ActiveRecord::Schema[7.0].define`).

6. **`belongs_to` becomes required by default in Rails 5.0.** 19 `belongs_to`
   associations. **Verified** that an `Event` with `service_id: nil` saves on 4.2,
   and nil service ids are legitimate here — `application_helper.rb:145` explicitly
   discusses a nil `service_id` having no `Service` row. So at the 5.0 step either
   set `config.active_record.belongs_to_required_by_default = false` in the
   `load_defaults` or add `optional: true` where nil is intended. Getting this
   wrong turns the ingest path into validation failures, which is the worst place
   in this app to be wrong.

7. ~~**`Rails.application.secrets`**~~ — **done at the 7.1 step.** Nothing was
   actually removed at 7.2, so the migration happened now rather than under time
   pressure. `config/secrets.yml` keeps only the production `ENV["SECRET_KEY_BASE"]`
   pass-through; the dev/test values moved to `config/environments/{development,
   test}.rb` as `config.secret_key_base = ENV["SECRET_KEY_BASE"] || '<committed>'`,
   and `require_secrets.rb` reads `ENV` directly instead of
   `Rails.application.secrets`. **Verified**: the resolved test key is unchanged
   (`26dc4b4e…`), `SECRET_KEY_BASE` still overrides it, production still fails
   closed with the custom message when the variable is unset, and the boot is
   deprecation-free. `credentials` was not adopted — it would mean shipping a
   `master.key` alongside the app for a single value that already arrives from
   `provision.sh`'s `/etc/DAD/environment`.

8. **`to_s(:db)`** — 10 call sites. **Verified deprecated on 7.0.8**
   (`Time#to_s(:db) is deprecated. Please use Time#to_fs(:db)`), and gone by 8.0.
   Mechanical, but it appears in the ingest path (`event.rb:459,478`) and in the
   statistics helpers, so a silent format change would corrupt stored timestamps.

9. **Zeitwerk at 6.0 — landed at the 6.1 step.** Rails 6.0 allowed
   `config.autoloader = :classic` to defer this, and classic is removed in 6.1, so
   the app now runs on Zeitwerk with no `config.autoloader` set. **Verified** the
   `$_models` boot hack in `config/application.rb` still yields the same 27 model
   names under Zeitwerk, and that `Rails.application.eager_load!` completes without
   raising — the eager `require` of every `app/models/**/*.rb` happens before
   `ActiveRecord::Base.subclasses` is read, so the ordering the nav bar depends on
   survives. Zeitwerk's own eager-load pass is what would have surfaced a
   filename/constant mismatch; none exist.

#### What the 5.2 → 6.1 step actually hit (landed)

Everything below was found by running the step, not predicted by the list above.
Recorded because the same class of failure recurs at 7.1.

- **`concurrent-ruby` no longer requires `logger`.** Boot died with
  `uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger`. Rails 6.1
  expects `Logger` to already be defined when activesupport loads; concurrent-ruby
  ≥ 1.3.5 stopped requiring it. Fixed with `require 'logger'` in `config/boot.rb`
  — **not** `config/application.rb`, because `bin/rails` loads
  `rails/commands` (and thus activesupport) *before* `application.rb`, so the
  require has to be in the file `bin/rails` reads first.
- **`codemirror-rails` caps `railties < 6.0`** and has had no release since 2016,
  so it cannot be bumped. Vendored instead: `codemirror.js`, the ruby mode, and
  `codemirror.css` under `vendor/assets/`. **Verified** the sprockets-built
  `application.js` and `application.css` are **byte-identical** to the 5.2 output
  (md5 `d88f67e6…` / `3fb16751…`), so the editor is a true drop-in.
- **`jbuilder` 2.7.0 is incompatible with 6.1.** Its `JbuilderTemplate` handler
  takes one argument; the 6.1 template compiler calls it with two, so *every*
  `.json.jbuilder` view died with `wrong number of arguments (given 2, expected 1)`
  — and only at render time, which the pre-existing suite barely exercised. Bumped
  to `~> 2.11` (resolves 2.13). **Verified** all 18 JSON endpoints return byte-for-
  byte the same bodies as 5.2, including that `sessions.json` still omits
  `session_hash` (§1.6).
- **`create_join_table` now raises on a re-declared column.** Two migrations
  (`CreateEventsWordsTable`, `CreateAlertsEventsJointable`) declared `event_id`/
  `word_id` inside the block, which duplicates the columns `create_join_table`
  already emits via `references`. 5.2 let the block silently win; 6.1 raises
  "you can't define an already defined column". This only bites a **from-scratch**
  `db:migrate` — CI runs exactly that, so it would have broken the build. Fixed by
  moving `limit: 8` into `column_options:` and dropping the block. **Verified** all
  29 migrations apply from scratch and the resulting `db/schema.rb` body and all 30
  `sqlite_master` objects are DDL-identical to 5.2.
- **Active Storage now needs `config/storage.yml` in production.** 5.2 only read
  that file when `config.active_storage.service` was set; 6.1 reads it whenever
  `ActiveStorage::Blob` is loaded, and `eager_load = true` loads it. Production
  died at boot with "Couldn't find Active Storage configuration". The app uses no
  attachments, so `config/storage.yml` exists purely to satisfy the loader.
- **`ActiveRecord::Base.configurations['test']['pool']` returns nil** on 6.1 (the
  hash was replaced by `DatabaseConfigurations`; the deprecated `[]` hands back a
  symbol-keyed hash). One test compared against that nil. Now uses
  `configs_for(env_name: 'test').first.pool`, which is the API that survives to 7.x.
- **`ActionDispatch::HostAuthorization` is new in 6.0** and appears in the
  production middleware stack. It is inert here because there is no
  `config.load_defaults`, so `config.hosts` is empty and everything is allowed —
  **verified** `/events` returns the same 302 on the same hosts as 5.2. It becomes
  a live restriction the moment `load_defaults 6.0` is adopted: at that point the
  real `ServerName` from `provision.sh` must be added to `config.hosts` or every
  request 403s.
- **Deliberately not done: `config.load_defaults`.** The 5.2 plan listed it for
  this step, but adopting `load_defaults 6.0` flips `belongs_to_required_by_default`
  (19 associations with legitimately nullable FKs — §5.2 item 6) *and* arms
  HostAuthorization, both silently. It is a reviewed change of its own, not a
  side effect of a version bump.

#### What the 6.1 → 7.1 step actually hit (landed)

Run against a pristine 6.1.7.10 worktree at `04d6f58` so every difference could be
attributed rather than assumed. Everything below was observed, not predicted.

- **Ruby 3.3.8 moved with Rails, and it forced three pins.** Ruby 3.3 ships
  `json` 3.x as a default gem; json 3.0 removed `quirks_mode`, which
  ActiveSupport 7.1 still calls from `active_support/json/encoding.rb`, so every
  `to_json` — and therefore all 34 jbuilder views — died with
  `unknown keyword: quirks_mode`. Pinned `json ~> 2.7` (resolves 2.19.3).
  Separately, minitest 6 changed `Minitest.after_run` to `(reporter, options)`;
  the Rails 7.1 test runner still calls it with one argument, and
  `activesupport 7.1.6` only declares `minitest >= 5.1`, so the 5.x line had to be
  pinned explicitly (`~> 5.25`, resolves 5.27.0). Nokogiri and sqlite3 both
  dropped Ruby 2.7, which is the real reason the Ruby jump could not wait for 7.2.
- **`to_s(:db)` is gone.** Replaced by `to_fs(:db)` in `event.rb`, `system.rb`,
  `application_helper.rb` and two tests. **Verified** the two produce byte-equal
  strings, so the SQL is unchanged.
- **Legacy `[[type, value]]` bind pairs are a hard failure, as item 1 predicted.**
  Six `exec_query` sites still passed them; on 7.1 that raises `TypeError: can't
  cast Array`. Now plain values. The `EventTest` bind-shape assertions and the
  `EXPLAIN QUERY PLAN` fixture were updated to match, so the search-path SQL is
  still asserted rather than just exercised.
- **`assets:precompile` broke, and this one was not on the list.** Rails 7.1's
  Active Storage, Action Cable and Action Text engines each append their own
  bundles to `config.assets.precompile`; 6.1's engines did not. Those bundles are
  ES6, and uglifier 2.7 — the compressor this app has always used — cannot parse
  them, so precompile died with `Unexpected token: name (FileChecksum)`. The app
  uses none of the three features (no `active_storage_*`/`action_text_*` tables, no
  ActionCable consumer, no trix in any view), so `config/initializers/assets_precompile.rb`
  turns Active Storage and Action Cable off through their own `precompile_assets`
  flags and subtracts the Action Text entries in `after_initialize` (Action Text
  has no flag, and its engine initializer appends after `config/initializers`
  runs). **Verified**: precompile then emits `application.js`, `application.css`
  and `spinner.gif` with digests **byte-identical to the 6.1 build**
  (`65f30ed2…` / `156e1108…`).
- **`rspec-rails` is load-bearing even though there is no `spec/` directory.** It
  was dropped as dead weight during the Gemfile rewrite and all four cucumber
  scenarios then failed with `undefined method 'expect'`: cucumber-rails only
  mixes `RSpec::Matchers` into `Cucumber::Rails::World` when
  `rspec/rails/matchers` is loadable. Restored (`~> 6.1`). Worth remembering —
  a gem with no obvious consumer is not the same as an unused gem.
- **Schema dump format changed, and exactly one table's DDL did.** `db/schema.rb`
  is now `ActiveRecord::Schema[7.1].define` and datetimes carry `precision: nil`.
  All 29 migrations still apply from scratch. Comparing `sqlite_master` object by
  object: 32 objects on both sides, same names, same types, and **only `events`
  differs** — 6.1 emits `"id" integer NOT NULL PRIMARY KEY`, 7.1 emits
  `"id" integer PRIMARY KEY AUTOINCREMENT NOT NULL`. It is the one table that
  `20261013000001_fix_generated_column_defaults` rebuilds through
  `change_column_default` (sqlite has no `ALTER COLUMN`), and the 7.1 adapter
  rebuilds with `AUTOINCREMENT` while 6.1 did not. Every column, type, default and
  index is unchanged; `AUTOINCREMENT` only affects rowid reuse after the largest id
  is deleted, which `events` never does. Worth knowing before §3.2 partitioning,
  though.
- **`Rails.application.secrets` migrated off, not just silenced.** CI showed a
  deprecation the local run had masked — `SECRET_KEY_BASE` was leaking into the
  local shell environment, so Rails took the ENV branch and never touched the
  deprecated `secrets` path. Fixed by keeping only the production ENV
  pass-through in `config/secrets.yml`, moving the committed dev/test keys to
  `config/environments/{development,test}.rb` as `config.secret_key_base`, and
  having `require_secrets.rb` read `ENV` directly. **Verified** the resolved test
  key is byte-identical to before, ENV still overrides, and production still
  refuses to boot without `SECRET_KEY_BASE`. Lesson: run the suite with a clean
  environment, not just a green one.
- **Three deprecations silenced rather than ignored.** `show_exceptions = false`
  → `:none` (exact equivalent), `check_pending!` → `check_all_pending!`, and
  `config.active_support.cache_format_version = 7.0` — the last is free here
  because nothing in the app reads or writes `Rails.cache`. The test run is now
  deprecation-free.
- **Two middleware dropped from the production stack, both inert here.** The stack
  went from 23 entries to 21: `ActionDispatch::HostAuthorization` and
  `ActiveSupport::Cache::Strategy::LocalCache`. HostAuthorization is now inserted
  only `unless Array(config.hosts).empty?` (6.1 inserted it unconditionally), so
  with no `config.load_defaults` it disappears rather than sitting there allowing
  everything — same net behaviour, and it means §5.2's earlier note is now
  *stronger*: setting `config.hosts` is what arms the middleware, so adding the
  real `ServerName` from `provision.sh` is a one-line change with no other
  coupling. LocalCache was simply removed from the default stack; irrelevant here
  because `perform_caching` is off in test and nothing touches `Rails.cache`.
- **Rails 7.1 sets `response_body = ""` on redirects**, so 302s now carry an empty
  body instead of the 97-byte `<html><body>You are being <a href=…>redirected</a>`
  stub. Status and `Location` are identical and no test or view reads the body, but
  anything that scraped the redirect stub would notice.
- **Assertion count rose 534 → 542 with no test logic changed.** The +8 is
  framework accounting: ActiveSupport 7.1's `assert_difference` /
  `assert_no_difference` route their block through minitest's
  `_assert_nothing_raised_or_warn`, which registers one assertion per call, where
  6.1's `assert_nothing_raised` registered none. The four affected files contain
  exactly 8 such calls (displays 2, jobs 2, sessions_admin 1, users_admin 3), and
  an isolated two-helper probe counts 4 assertions on 7.1 against 2 on 6.1. Runs
  stayed at 194.
- **Functional equivalence, verified rather than assumed.** A deterministic probe
  (fixed seed data, no `SecureRandom`, explicit timestamps) drove every HTML and
  JSON route plus the search/dashboard endpoints on both versions. All 200/302
  statuses match; all JSON bodies are byte-identical; HTML pages are identical
  modulo attribute *ordering* (`<link rel=… media=…>` vs `<link … media=…>`),
  per-request CSRF/session randomness, and bcrypt salts on `/users`.
  `rake test` 194 runs green, `cucumber` 4 scenarios / 15 steps green, production
  boot clean, `assets:precompile` clean.

#### The asset stack is the least pleasant part

`sprockets 2.12.5` / `sprockets-rails 2.3.3` / `sass-rails 4.0.5` /
`coffee-rails 4.0.1` / `uglifier 2.7` / `turbolinks 2.5` / `jquery-rails 3.1` /
`codemirror-rails 5.16` (last released 2016) / `jbuilder 1.2`.

Rails 8 defaults to **Propshaft**; Sprockets 4 is the ceiling for Rails 7 and is
not the Rails 8 default. `sass-rails` and `coffee-rails` are both unmaintained
(successors: `dartsass-rails`, and hand-written JS). Converting 14 `.js.coffee`
files is only **84 lines total** — trivial to do by hand rather than with a
transpiler. `turbolinks 2.5` uses `data-no-turbolink` (5 sites) and
`data-turbolinks-track` (2 sites), both dropped by Turbolinks 5 and replaced by
different semantics under Turbo. `jbuilder 1.2` → 2.x across 34 views is a real
but mechanical sweep.

**That `production.rb:31` question is now answered — it is not a bug.** Verified
on a real production boot at Rails 7.1.6: `config.assets.enabled = false` is
ignored by sprockets-rails 3.x, `config.assets.digest = false` makes the layout
emit the **undigested** `/assets/application.js`, and that URL returns **200** with
the full 432,819-byte bundle. It works because `config.assets.compile` is left at
its default `true` (line 30 is commented out), so sprockets resolves and serves the
logical name on demand. The digested path resolves too. Identical behaviour on 6.1
(`production.rb` is untouched by this step), so nothing regressed — but note that
production is doing **on-the-fly compilation on every cold boot**, and
`provision.sh` never runs `assets:precompile`. Setting `compile = false` and
precompiling at deploy time is the cheap fix; leaving it as-is costs boot latency
and a sprockets cache miss per request until the cache warms.

#### Test and deployment stack

**Already moved by step 3:** Bundler 2.6.7, `pg 1.7`, `sqlite3 1.7.3`,
`nokogiri 1.19`, `bcrypt 3.1.20`, `cucumber-rails 2.6`, `rspec-rails 6.1`,
`rack 2.2`. **Still outstanding for 7.2/8.1:** `capybara` → 3.40,
`database_cleaner` → 2.x, and `sqlite3` 2.x (which Rails 7.2+ wants and which the
current `~> 1.7, < 2` ceiling blocks — the ceiling exists because Rails 7.1's
adapter predates the 2.x API, not because of Ruby). `rack 1.6` → 3.x is low-risk
here because the app defines
`ActionController::TestCase`; `test_helper.rb:26` declares `fixtures :all` but
there are no fixtures. `rack 1.6` → 3.x is low-risk here because the app defines
**no custom middleware** (verified: zero `middleware` references in `config/`,
`app/`, `lib/`). CI (`ruby-version`) and `Dockerfile.dev` (`FROM ruby:`) both
moved to 3.3.8 at step 3, and §1.2's advisory security gates become blocking at the end.

#### Recommended sequence

| Step | Ruby | Main work |
|---|---|---|
| **0. Prepare (on 4.2, today)** | 2.7.8 | Items 1–4: `sanitize_sql_array`, `before_action`, delete dead deps, replace the `$_models` boot hack. All back-portable, all reduce later risk. |
| **1. → 5.2** | 2.7.8 | **Done.** Migration brackets (item 5), `belongs_to` decision (item 6). `load_defaults` deliberately *not* adopted — see the note below the table. |
| **2. → 6.1** | 2.7.8 | **Done.** Zeitwerk now mandatory (item 9). Sprockets stayed on 3.7.5 (4 is not required at this step). |
| **3. → 7.1** | **3.3.8** | **Done.** Ruby jumped here rather than at 7.2 — nokogiri and sqlite3 had already dropped 2.7, and Ruby 3.3's `json` 3.x default gem forced a pin. `to_fs(:db)` (item 8), `exec_query` binds (item 1), the precompile-list fix. |
| **4. → 7.2** | 3.3.8 (no change) | Now a pure Rails step. `Rails.application.secrets` (item 7) was already migrated at step 3, so nothing is pre-gated here. `sqlite3` 2.x ceiling lifts. |
| **5. → 8.1** | 3.3.8 (no change) | Propshaft, Turbo, `dartsass-rails`. Target 8.1, not 8.0: 8.0 gets security fixes only to Nov 2026, 8.1 to Oct 2027. |

**Do §4.3 first.** The suite is 194 runs against 90 views and the ingest path, and
the two most dangerous items above (6 and 8) both fail *silently* — dropped nav
entries, validation failures, reformatted timestamps — rather than loudly. Request
specs over the CRUD routes and the ingest entry points are the prerequisite that
makes each of the five steps verifiable; without them this is a multi-week change
validated by eyeballing a dashboard.

Worth treating as the main long-running workstream rather than a task.

### 5.3 One malformed log line still kills the collector **[operations] [correctness]**

The old review marked "`puts` as the only observability" as fixed. Only a narrow
slice of it was: the SQL-echoing `puts` in `search`/`search_period`/
`approximate_count` are gone. The two parts that actually mattered are not:

```ruby
rescue Exception => e
  puts "Error processing " + in_flight
  puts e
  puts "Offending line: " + line
  Event.flush_and_wait
  LogQueue.write_offset(in_flight, line_start)
  exit 1
end
```

`import_syslog.rb:43` still rescues `Exception` rather than `StandardError`, and
still `exit 1`s. So a single unparseable line terminates the importer. Combined
with §5.1 -- the process is backgrounded with no restart -- one bad line means
**ingestion stops silently and stays stopped**. The checkpoint handling around it
is correct (the offset is rewound so the line is retried, not skipped), but
retrying the same line on restart means it fails and exits again: a poison
message wedges the pipeline permanently.

There are also 25 `puts` calls and **zero** `logger` calls across `app/`, `lib/`,
`import_syslog.rb` and `scheduler.rb`.

**Fix:** rescue `StandardError` per line, count failures into a `Statistic`, log
the offending line at `warn`, and continue. Reserve the hard exit for errors that
genuinely invalidate the run. Move `puts` to `Rails.logger` so severity and
timestamps survive into the Passenger log.

Higher priority than it looks: this is the most likely way the system silently
stops collecting, and §5.1 means nothing brings it back.

### 5.4 No LICENSE **[operations]**

Still no license file. On GitHub that means all rights are reserved by default,
so downstream use is legally blocked. If DAD is meant to be open source, pick one
and add it.

### 5.5 The README is a 2014 status note **[operations]**

`README` (11 lines) and `README.rdoc` (12 lines) are near-duplicates describing
work planned for "January of 2015", with insert rates as the headline metric.
Neither tells an operator how to install, configure, or run the importer,
scheduler, or syslog collector.

Keep one file, delete the other, and write the operational sections: required
environment variables (`SECRET_KEY_BASE`, `DAD_DB_*` / `DATABASE_URL`), how the
three processes fit together, and where logs go.

---

## 6. Recommended sequence

| Priority | Item | Effort | Why here |
|---|---|---|---|
| 1 | §1.1 production secret: rotate + secret scanning | hours | Impersonation risk if any deployment still uses the 2015 key |
| 2 | §1.2 make brakeman blocking (baselined) | hours | Cheap, stops new sinks landing |
| 3 | §4.1 option A: subprocess coverage of threaded ingest | hours | Nearly free — harness exists |
| 4 | §5.3 poison-line handling + `Rails.logger` | hours | Stops silent ingestion stalls; compounds §5.1 |
| 5 | §5.1 systemd units | days | The importer dying silently is the main operational risk |
| 5b | ~~§5.2 step 0: back-portable prep~~ **done** | — | Landed with the 5.2 step |
| 6 | §5.2 Rails **7.2 → 8.1** (5.2, 6.1 and 7.1 landed; see the staged plan there) | weeks, not months — the Ruby jump is already done | Gates §3.2, §4.1-C, and blocking security gates |
| 7 | §3.2 partitioning, §3.3 FTS, §4.1-B `EventIngestor` | ongoing | Real work, but bounded by the above |
| 8 | §5.4 LICENSE, §5.5 README, §4.2 dead code | hours | Hygiene; do opportunistically |

**The pattern worth acting on.** Three separate findings in this review — the
importer that died at startup while CI stayed green, the four broken admin
screens, and the checkpoint bugs — have the same cause: nothing exercises the
entry points. The `__FILE__ == $PROGRAM_NAME` guard added in PR #16 and request
specs over the CRUD routes are the two structural fixes for it. Priorities 1 and 3
are both versions of the same investment.

---

## Appendix: what is closed, and where the detail is

Section numbers below are from the **original** review, which is a different
numbering from this document. Where an old number collides with a new one, the
content is named so the reference is unambiguous.

Verified closed against the current tree:

| Old item | What it covered | PR |
|---|---|---|
| 1.1 | SQL injection in the search path | #1 |
| 1.2 | Two `eval` sinks (RCE as root) | #4 |
| 1.3 | Password hashing broken by construction | #4 |
| 1.4 | Password hashes leaking through the JSON API | #4 |
| 1.5 | Secrets committed to the repo (working tree only -- see §1.1 above) | #6 |
| 1.6 | Session id generation | #4 |
| 1.7 | XSS in the event renderer | #7 |
| 1.8 | Copy-pasted, inconsistent authorization | #8 |
| 2.1 | Empty dashboard when there are no exclusions. **The original `Regexp.union([])` diagnosis was wrong** -- that returns `/(?!)/`, which matches nothing. The real cause was a *blank* pattern: `Regexp.union([""])` is `//`, which matches everything | #11 |
| 2.2 | Hard-coded 2014–2019 timestamp window | #10 |
| 2.3 | `Math` core module reopened -- carried a user-visible bug | #12 |
| 2.4 | Ingestion not crash-safe | #15 |
| 2.5 | `storeEvent` mangling data to dodge quoting bugs | #1 |
| 3.1 | Missing `events_words` indexes | #2 |
| 5.3 | Test suite red and misleading | #3 |
| 5.4 | **Partly.** The SQL-echoing `puts` in the search path are gone (#12); the rest was never done and is re-opened as §5.3 above | #12 |
| 6.3 | Duplicated state block in `Event` | #14 |
| 6.4 | `ProcessedLogs` retention replacing a no-op `purge_logs` | #13 |
| 7.1 | `NameError` that made `import_syslog.rb` dead on arrival | #16 |
| 7.2 | Crash-then-reclaim duplicating rows | #17 |
| 6.5 | The three dashboard N+1s, `has_right?`, `criticality_name`, `resources :positions`, `Service has_many :servers`, the empty migration, dev/test secret rotation | #18 |
| — | Ingest throughput measured after the queue reset (a regression introduced by #17): the dashboard EPS chart read 0.0 and `@bulk_insert_size` grew +20 per flush with no ceiling | #22 |
| §3.1 | Statistics helpers re-running the same grouped query per reduction; `system_service_stats` N+1 (4 finds → 0); duplicate `hourly_stats` call in the dashboard template (5 grouped queries → 4 per render) | this branch |
| §2.1 | Four admin screens: `sessions#index`/`#show` 500'd on removed route helpers; `jobs#test` 500'd on nil `@job`; `Users#destroy` orphaned Session rows and 500'd subsequent requests; `Users#update` locked accounts out on a blank password and could persist plaintext; `Users#create` accepted an empty password. Plus request-spec coverage for all of it | #23 |

The superseded review revisions -- including the misdiagnoses and the reasoning
that corrected them -- are preserved in git:

```
git show 104abd4:RECOMMENDATIONS.md   # through old §7, at the retention merge
git show b759c51:RECOMMENDATIONS.md   # adds old §7.1–7.5, the merge regressions
```

---

*This review was produced by an AI agent (OpenHands) on behalf of the user.*
