# DAD — Open Recommendations

Scanned at `b6adf25` (2026-10-14); §2.1 re-verified and closed at the branch
adding `users_admin_test.rb`. Re-verified again at `854f641` (2026-10-15) after
the post-upgrade cleanup: §1.2 closed, a new §1.3 found and closed, §4.3 gaps
closed. PRs #1–#23 all merged.

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
| SQL injection, `eval` sinks, password hashing, XSS, authorization | Closed |
| Password hashes in HTML | **Was open — closed at `365c845` (§1.3)** — PR #4 fixed the JSON API leak; the three HTML views were missed |
| Secrets in the working tree | Closed — **but a production key is still in git history (§1.1)** |
| Ingestion crash-safety and idempotency | Closed, at-least-once (§2.2) |
| Search indexing, dashboard SQL portability, timestamp parsing | Closed |
| Test suite | Green: 218 runs / 624 assertions, 4 cucumber scenarios |
| Admin screens (sessions, users, jobs) | Closed — now covered by request tests (§2.1) |
| Poison line / observability | **Open — was mis-marked as fixed (§5.3)** |
| Rails upgrade | **Closed: 4.2 → 5.2 → 6.1 → 7.1 → 7.2 → 8.0 → 8.1.4 landed** (§5.2, tag `rails-8.1.4`) |
| Rails EOL | Closed — Rails is on the current stable line (8.1, supported to Oct 2027) |
| CI security gates | **Closed — both gates now blocking**, 0 advisories, 0 Brakeman warnings (§1.2) |
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

### 1.2 ✅ Closed — CI security gates were advisory, not blocking **[security] [operations]**

`.github/workflows/ci.yml` lines 56 and 60 run `bundle-audit` and `brakeman` with
`continue-on-error: true`. Both are currently informational, so a new vulnerable
gem or a new injection sink merges green.

After the 4.2 → 5.2 step, Brakeman reports **2 warnings** (down from 3) and
bundle-audit advisories drop from **88 to 46** — the Rails/rack/actionpack
framework CVEs are gone; what remains is mostly transitive (`rdoc`, `sqlite3`).
Measured again after the 6.1 → 7.1 step: Brakeman is unchanged at **1 warning**
(one high-confidence finding, pre-existing), and bundle-audit advisories fall from
**40 to 25**. The `json 1.8.6`, `rdoc` and 17 `nokogiri` advisories are gone; what
remained was 10 × `sqlite3` (the dev/test-only gem, capped at 1.7.3 by the
`< 2.0` ceiling — see §5.2), 6 × `activestorage` (an engine this app does not use
at all), and `httparty`/`jquery-rails`/`mail`/`actionview`.

Measured a third time after the 7.1 → 8.1.4 steps: **25 → 4**. The `sqlite3` and
`activestorage` advisories are gone (sqlite3 moved to 2.10 once Rails 8.0 allowed
it), and no framework advisory remains. What is left is entirely non-framework:

| Gem | Version | Advisories | Fix |
|---|---|---|---|
| `httparty` | 0.18.1 | CVE-2024-22049 (Med), CVE-2025-68696 (**High**) | Upgrade, or delete — it is referenced nowhere in `app/`, `lib/` or `test/` |
| `jquery-rails` | 4.3.5 | CVE-2020-11023, CVE-2020-23064 (both Med) | Bump to `~> 4.4` |

**Closed at `bbdd4b4`.** All four advisories cleared and both gates are now
blocking (`continue-on-error` removed from both steps):

- `httparty` — **deleted**, not bumped. The Gemfile comment claimed it was "For
  JSON requests for the IP Address blocking service"; no such code exists anywhere
  in `app/`, `lib/`, `test/`, `features/` or the root scripts. It was dead weight
  carrying the only High-severity item.
- `jquery-rails` — bumped to 4.6.1 **and** the manifest switched from
  `//= require jquery` to `//= require jquery3`. The bump alone would not have
  cleared either CVE: both are jQuery *core* advisories fixed in jQuery 3.5.0, and
  jquery-rails still ships 1.12.4 as `jquery.js`. `require jquery` resolved to
  1.12.4 — confirmed by grepping the built bundle. Switching the manifest is what
  actually ships 3.7.1. That required patching the vendored `highcharts-custom.js`
  adapter, which used `.bind()`/`.unbind()` (removed in jQuery 3.0); exactly two
  call sites, now `.on()`/`.off()`.
- Brakeman reports **0 warnings**, so no ignore file was needed.

A CI step now greps the compiled `application-*.js` and fails unless it contains a
jQuery 3 header and does *not* contain 1.12.4 — otherwise a silent revert to
`require jquery` would re-introduce both CVEs with every other check green.

---

### 1.3 ✅ Closed — bcrypt password hashes were rendered into user-admin HTML **[security]**

PR #4 closed old §1.4, "password hashes leaking through the JSON API", by
whitelisting attributes in the jbuilder views. The **HTML** views were never
fixed, and the status snapshot's "hash leakage — Closed" line has been overstating
the position ever since. Three of the four user views interpolated the `password`
column, which holds a bcrypt hash:

| View | Code | Effect |
|---|---|---|
| `users/index.html.erb` | `<td><%= user.password %></td>` | every account's hash on one page |
| `users/show.html.erb` | `<%= @user.password %>` | one account's hash |
| `users/_form.html.erb` | `f.text_field :password` | prefills the hash into a **visible** input on edit |

Admin-gated is not a sufficient answer: the hash leaves the trust boundary once it
is in HTML — browser history, proxy/CDN logs that capture bodies, error reporters,
and any XSS on the page (§1.7 exists because event and system text is
attacker-controlled). For bcrypt the hash *is* the password-equivalent, so
exposing it enables offline cracking without touching the login endpoint or its
lockout.

The edit form was also a **functional** bug. A browser submits what the form
rendered, so opening a user, editing the name, and pressing Save without touching
the password field submitted the stored hash as the new password; `#update` saw a
present value and re-hashed it, storing `bcrypt(old hash)`. Reproduced end to end:
the account could no longer log in with its real password. The pre-existing
"updating without a password leaves the existing password working" test could not
catch this — it only covered the field being absent or empty, never prefilled.

**Closed at `365c845`:** Password column and paragraph removed; `text_field` →
`password_field` (Rails renders password fields with `value: nil`, so the hash is
never sent to the browser). `credential_exposure_test.rb` pins all of it, including
the browser round-trip; against the pre-fix views those tests produce 4 failures.

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

### 4.2 ✅ Closed — dead and duplicated code **[maintainability]**

Closed at `4ee7458`.

- `Event.search` / `Event.search_period` merged into one `search` taking a
  `Range`. The merge surfaced a test that was passing for the wrong reason: the
  cucumber step passed `0` as the time bound, `'0'.to_fs(:db)` is the string
  `"0"`, and the resulting `BETWEEN '0' AND <now>` matched everything. The
  scenario named "Searching for an event that is in the correct time frame" was
  not testing a time frame. Fixed, and a negative scenario added (search a window
  that excludes the event, assert it is not found) — without it, a search that
  ignored its range entirely would still pass. Mutation-checked.
- `System#hourly_stats` / `#events_per_hour` and the `ApplicationHelper`
  statistics methods: already closed by §3.1 (`BucketStats` + shared
  `hourly_buckets`), verified against the current tree rather than assumed.
- `export_logs.rb` moved to `bin/export_logs`, and its `require` made relative to
  `__dir__` so it no longer only works from the repo root.
- `syslog.pl`: **the original claim was half wrong.** `$Filename` was always
  declared with `my`. The real defect was the declaration line
  `my $Filename, $RotateTime = 0;`, which Perl parses as two arguments to `my` —
  `$Filename` lexical, `$RotateTime` a *global* assigned 0. Fixed to
  `my ($buf, $Filename, $RotateTime)`. Also: the `open(LOG, ...)` was unchecked,
  so a failed open meant every later `print LOG` went to a closed handle and the
  collector silently discarded every packet it received; and `$DEBUG` is now
  driven by `DAD_SYSLOG_DEBUG` instead of being hardcoded to 0, which makes the
  `if($DEBUG)` branch reachable rather than dead.
- 12 empty `.js.coffee` and 14 comment-only `.css.scss` scaffold stubs deleted.
  Both manifests use `require_tree .`, so this was verified rather than assumed:
  precompiled with and without the stubs and diffed the bundles. CSS hash
  byte-identical; the JS difference is only the empty `(function(){}).call(this)`
  wrappers comment-only CoffeeScript compiles to — 18,772 non-blank code lines on
  both sides.


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

### 4.3 ✅ Closed — the suite was shallow on the routes that broke **[maintainability]**

218 runs / 624 assertions, plus 4 cucumber scenarios.

The admin CRUD request specs called for in the previous revision exist
(`users_admin_test.rb`, `sessions_admin_test.rb`), which is what closed §2.1. The
two remaining gaps are now closed at `854f641`:

- `role_grant_test.rb` — the `roles`/`role_add`/`role_remove` escalation path,
  including that granting Admin confers every right, that the endpoint is itself
  gated against a non-admin, and that re-granting does not duplicate the join row.
- `alert_acknowledge_test.rb` — `acknowledge` (HTML and JS branches) and `ackall`,
  plus the index filter that keeps closed alerts out of the open queue.

Writing those tests surfaced one real bug, fixed at `5ab2ca4`: `User#right_names`
memoised the resolved right list and nothing ever cleared it, so `reload` returned
a user whose rights read stale (`user.roles << admin_role; user.reload;
user.has_right?('Admin') # => false`). Latent rather than live — `role_add`
redirects, so the next request loads a fresh instance — but it sits directly
underneath the authorisation check every controller funnels through.

**Two things the tests pin down rather than fix, needing a decision:**

1. ~~`acknowledge` and `ackall` are **GET**~~ — **resolved at `60aedf6`**: both are
   now POST (`post 'acknowledge'` / `post 'ackall'` on the routes, `button_to ... method: :post` in the view), so
   `protect_from_forgery` applies and a prefetched link or injected `<img>` can no
   longer close alerts. The existing tests were updated rather than replaced, so
   they still pin the queue-filter and criticality behaviour.
2. `ackall` is unscoped and unconfirmed — one request closes the entire queue,
   including alerts another operator was about to work.

One known flake: an intermittent `SQLite3::BusyException` in the threaded-path
tests. It is the same single-writer constraint as §4.1 and predates all recent
work. Confirmed by rerun — a failing run passes immediately afterwards.

---

## 5. Operations

### 5.1 ✅ Closed — provisioning is idempotent and the services are under systemd **[operations]**

Closed at `bf547e0`.

`provision.sh` is idempotent: secrets are generated once into `/etc/DAD/environment`
and reused on re-run (so re-provisioning does not invalidate sessions or rotate the
DB password out from under the app), `ln -sfn` instead of `ln -s`, and every
`cat > file` is now guarded. `db/seeds.rb` is idempotent and covered by a
regression test that runs the seed twice and asserts nothing duplicated; it
deliberately does not reset an admin password that has been changed.

Three systemd units added (`systemd/dad-{importer,scheduler,syslog}.service`),
`Restart=always` with `journalctl`-visible output, `dad-syslog` unprivileged via
`CAP_NET_BIND_SERVICE` rather than root. A CI job now runs `bash -n provision.sh`
and `systemd-analyze verify` on the units — it was confirmed to catch an invalid
unit key, so the gate is real rather than decorative.

One placement bug found while writing them: `StartLimitIntervalSec` belongs in
`[Unit]`, not `[Service]`; in `[Service]` systemd ignores it and warns.


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

### 5.2 ✅ Closed — the Rails 8 upgrade has landed **[operations]**

`Gemfile` now pins `rails '~> 8.1.0'` (resolves **8.1.4**), tagged `rails-8.1.4`.
Every step of the sequence at the end of this section has landed: 4.2 → 5.2 → 6.1
→ 7.1 → 7.2 → 8.0 → 8.1, one commit per minor step. Rails is on the current
stable line (8.1 gets security fixes to October 2027), so the EOL rationale that
kept bundle-audit non-blocking (§1.2) is gone. Ruby stayed at 3.3.8 for the whole
of it — 3.3.8 was already above the 7.2 (3.1) and 8.1 (3.2) floors.

The plan below is kept in full: it is the record of *why* each pin and each
config change exists, and the remaining sections are still accurate as history.
The "What the 7.2 → 8.1 steps actually hit" subsection at the end records what
the last three steps really required.

This is the dependency that gates several other items: Postgres partitioning
(§3.2) and a Postgres test database (§4.1 option C) both become tractable during
a Rails upgrade, and the CI security gates can only be made blocking afterwards.

**Baseline at the start of this workstream.** Rails 4.2.11.3 · Ruby 2.7.8 ·
Bundler 1.17.3 · rack 1.6.13 · sprockets 2.12.5 · SQLite in dev/test, Postgres in
prod (`pg 0.21.0`). **Current baseline after all steps:** Rails **8.1.4** ·
Ruby 3.3.8 · Bundler 2.6.7 · rack 2.2 · sprockets 3.7.5 · jbuilder 2.15 ·
nokogiri 1.19 · pg 1.5 (production group, not exercised by CI) · sqlite3 2.10 ·
json 3.1 (floor raised at the 8.1 step, once Rails stopped passing `quirks_mode`)
· minitest 5.27 (still pinned off 6.x) · mail 2.9 · cucumber-rails 3.1.
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

**Landed across steps 3–6:** Bundler 2.6.7, `pg 1.5` (production group),
`nokogiri 1.19`, `bcrypt 3.1.20`, `rspec-rails 6.1`, `capybara 3.40`, `rack 2.2`.
`sqlite3` went 1.7.3 → **2.10** at the 8.0 step (the `< 2` ceiling existed because
Rails 7.x's adapter predates the 2.x API, not because of Ruby), and
`cucumber-rails` 2.6 → **3.1** for the same reason. `database_cleaner` stayed on
**1.99** — cucumber-rails 3.1 still accepts it, so the 2.x split was never forced.
`rack` stayed on **2.2**: Rails 8.1 supports it, and moving to 3.x is optional.
`rack 1.6` → 3.x was low-risk here because the app defines **no custom middleware**
(verified: zero `middleware` references in `config/`, `app/`, `lib/`). CI
(`ruby-version`) and `Dockerfile.dev` (`FROM ruby:`) both moved to 3.3.8 at step 3
and needed no further change.

#### Recommended sequence

| Step | Ruby | Main work |
|---|---|---|
| **0. Prepare (on 4.2, today)** | 2.7.8 | Items 1–4: `sanitize_sql_array`, `before_action`, delete dead deps, replace the `$_models` boot hack. All back-portable, all reduce later risk. |
| **1. → 5.2** | 2.7.8 | **Done.** Migration brackets (item 5), `belongs_to` decision (item 6). `load_defaults` deliberately *not* adopted — see the note below the table. |
| **2. → 6.1** | 2.7.8 | **Done.** Zeitwerk now mandatory (item 9). Sprockets stayed on 3.7.5 (4 is not required at this step). |
| **3. → 7.1** | **3.3.8** | **Done.** Ruby jumped here rather than at 7.2 — nokogiri and sqlite3 had already dropped 2.7, and Ruby 3.3's `json` 3.x default gem forced a pin. `to_fs(:db)` (item 8), `exec_query` binds (item 1), the precompile-list fix. |
| **4. → 7.2** | 3.3.8 (no change) | **Done.** Was a pure Rails step; `Rails.application.secrets` (item 7) had already migrated at step 3. `mail` had to move off `~> 2.7.0` (actionmailer ≥ 7.2 needs `mail >= 2.8`). `sqlite3` ceiling did *not* lift here — 7.2 still accepts 1.x; it lifted at 8.0. |
| **5. → 8.0** | 3.3.8 (no change) | **Done** (inserted as its own step rather than jumping 7.2 → 8.1). `sqlite3` → `~> 2.1` (8.0's adapter *requires* ≥ 2.1) and `cucumber-rails` → `~> 3.1` (2.6.x caps `railties < 8`). |
| **6. → 8.1** | 3.3.8 (no change) | **Done.** `json` → `~> 3.1` — the step every earlier pin was waiting for. Propshaft / Turbo / `dartsass-rails` deliberately **not** adopted: they are opt-in modernisation, not requirements of 8.1, and Sprockets 3.7.5 + uglifier 2.7 still build byte-identical output. |

**Do §4.3 first.** The suite is 194 runs against 90 views and the ingest path, and
the two most dangerous items above (6 and 8) both fail *silently* — dropped nav
entries, validation failures, reformatted timestamps — rather than loudly. Request
specs over the CRUD routes and the ingest entry points are the prerequisite that
makes each of the five steps verifiable; without them this is a multi-week change
validated by eyeballing a dashboard.

Worth treating as the main long-running workstream rather than a task.

#### What the 7.2 → 8.1 steps actually hit (landed)

The prediction that these would be "pure Rails steps with no Ruby work" held, but
they were not no-ops. Each step was verified against a `git worktree` pinned at the
previous upgrade commit, comparing the full test suite, cucumber, the route table,
a byte-digest of every GET route, ~30 model-layer probes, and `assets:precompile`
output.

**7.1 → 7.2.3.2**
- `mail ~> 2.7.0` was the blocker: `actionmailer >= 7.2.0` requires `mail >= 2.8`,
  so Rails 7.2+ was simply unresolvable. The app has no mailers and never
  references `Mail`, so relaxing to `~> 2.8` is free.
- `sqlite3` stayed `< 2` — 7.2's adapter accepts 1.4 or 2.x, so the ceiling was
  not the constraint anyone expected at this step.
- New deprecation: leaving `ActiveSupport.to_time_preserves_timezone` unset.
- Result: routes identical, all 145 GET samples byte-identical, all probes
  identical, assets byte-identical.

**7.2 → 8.0.5.1**
- `sqlite3` → `~> 2.1`: the 8.0 adapter *requires* ≥ 2.1 (it uses the 2.x
  `SQLite3::Statement`/`Database` API). Precompiled x86_64-linux wheels mean no
  local toolchain is needed.
- `cucumber-rails ~> 2.6` → `~> 3.1`: 2.6.x caps `railties < 8`. This, not Rails
  itself, is what blocked 8.0 and 8.1. 3.1.x is the oldest line accepting
  railties 8 and keeps `features/support/env.rb` unchanged; `database_cleaner
  1.99` still satisfies it. `rspec-rails 6.1.5` needed no change.
- `to_time_preserves_timezone = true` became deprecated in favour of
  `config.active_support.to_time_preserves_timezone = :zone`. Because this app
  calls **no** `config.load_defaults`, the 8.0 default is not applied on its own —
  the value has to be set by hand. Setting `:zone` here made the 8.1 step
  provably neutral.
- Result: routes identical, all 145 GET samples byte-identical, all probes
  identical, assets byte-identical. Zero behavioural change.

**8.0 → 8.1.4**
- `json ~> 2.7` → `~> 3.1`. This is the step the pin existed for: ActiveSupport
  ≤ 8.0 called `JSON.generate(jsonified, quirks_mode: true, max_nesting: false)`
  and json 3.x removed the keyword, so the pin was load-bearing through 7.1, 7.2
  and 8.0 (it would have killed every `to_json` and all 34 jbuilder views). 8.1.4
  calls plain `JSON.generate(jsonified)`.
- `config.active_support.to_time_preserves_timezone` removed — 8.1 hardcoded the
  `:zone` behaviour it was already set to, so the setting became a warning-only
  no-op.
- `DatabaseConfigurations#pool` renamed `#max_connections` (old name deprecated,
  gone in 8.2). `test/models/event_ingest_flush_test.rb` read the deprecated
  accessor and warned on every run.
- **The one visible behaviour change:** 8.1 rebuilt `utf8_enforcer_tag` from a raw
  string literal into a `tag()` call, so every form's utf8 enforcer input now
  renders `type="hidden"` before `name="utf8"`. 12 of 145 sampled pages changed,
  each in exactly that one place — same attribute set, same value, same encoding.
  Verified mechanically by rewriting the 8.0 markup into the 8.1 form and
  confirming the documents then match byte-for-byte. Cosmetic, but it is the kind
  of diff that is only provable rather than assumed.
- Result: routes identical, all model probes identical, 133/145 GET samples
  byte-identical (the other 12 = the utf8 tag), assets byte-identical.

**Method note (worth repeating for the next upgrade).** A cross-version probe is
only trustworthy once it is deterministic. Three things had to be pinned down:
the clock (frozen — `datetime_select` embeds `Date.today`/`Time.now` in option
values, which otherwise changes every page), fixture loading *before* the probe's
auth setup (Rails 7.1+ hashes fixture labels, so ids are stable and identical in
both trees), and normalising bcrypt hashes, object addresses and now-derived
timestamps out of the digest. Without those, the diff is noise; with them, the
7.1→7.2 and 8.0→8.1 diffs came back genuinely empty.

**Still open after the upgrade:** §4.3 (request-spec coverage) remains the real
gap — the probe harness lives in `/tmp` and is not committed, so the next upgrade
still starts from 194 unit runs against 90 views. And the two non-framework
advisories in §1.2 (`httparty`, `jquery-rails`) are now the only thing standing
between this repo and blocking CI security gates.

### 5.3 ✅ Closed — a malformed line no longer kills the collector **[operations] [correctness]**

Closed at `c5d82ab` (behaviour) and `94654d1` (the subprocess coverage that
exercises it).

`rescue Exception` + `exit 1` became `rescue StandardError` per line: the bad line
is logged at `warn` with its text and byte offset, counted, and recorded as a
`Statistic` series so a rising failure rate is visible instead of silent, and the
pass continues. Non-`StandardError` still stops the run and rewinds the
checkpoint, because those errors genuinely invalidate the pass. The `puts` calls
are `Rails.logger`; both daemons additionally broadcast to stdout so severity and
timestamps reach the journal.


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

### 5.4 ✅ Closed — MIT LICENSE added **[operations]**

Closed at `68a6c39`. MIT, copyright "2007-2026 David Hoelzer". Chosen to match the
MIT dependency tree and to impose nothing on operators running it as a service.
This is a judgement made on the maintainer's behalf and is trivially reversible —
see the commit message for the reasoning and the caveat about contributor consent.


Still no license file. On GitHub that means all rights are reserved by default,
so downstream use is legally blocked. If DAD is meant to be open source, pick one
and add it.

### 5.5 ✅ Closed — the README is operator documentation **[operations]**

Closed at `58407e9`. One file kept (`README.md`), `README` and `README.rdoc`
deleted. Now documents the pipeline diagram, every environment variable and which
component reads it, where secrets live and why there are two files, install two
ways, the three different meanings of "logs", and the ingest semantics that
previously lived only in `event.rb` comments.

Two claims in the draft were checked and found wrong, and the README now states
the truth: `DATABASE_URL` **takes precedence** over the `DAD_DB_*` variables
(verified by setting both and reading `connection_db_config.database`), and only
`import_syslog.rb` handles `Interrupt` — `scheduler.rb` has no interrupt handling
at all.


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
| 2 | ~~§1.2 make security gates blocking~~ **done** (`bbdd4b4`, 0 advisories / 0 warnings) | — | — |
| 2b | ~~Decide on §4.3's GET-with-side-effects~~ **done** (`60aedf6`, both now POST) | — | — |
| 3 | ~~§4.1 option A: subprocess coverage of threaded ingest~~ **done** (`94654d1`) | — | — |
| 4 | ~~§5.3 poison-line handling + `Rails.logger`~~ **done** (`c5d82ab`) | — | — |
| 5 | ~~§5.1 systemd units~~ **done** (`bf547e0`) | — | — |
| 5b | ~~§5.2 step 0: back-portable prep~~ **done** | — | Landed with the 5.2 step |
| 6 | §5.2 Rails **7.2 → 8.1** (5.2, 6.1 and 7.1 landed; see the staged plan there) | weeks, not months — the Ruby jump is already done | Gates §3.2, §4.1-C, and blocking security gates |
| 7 | §3.2 partitioning, §3.3 FTS, §4.1-B `EventIngestor` | ongoing | Real work, but bounded by the above |
| 8 | ~~§5.4 LICENSE, §5.5 README, §4.2 dead code~~ **done** (`68a6c39`, `58407e9`, `4ee7458`) | — | — |

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
| §1.2 | All four remaining bundle-audit advisories cleared (`httparty` deleted as unused; `jquery-rails` 4.6.1 **plus** `//= require jquery3`, which is what actually ships jQuery 3.7.1 — the gem bump alone ships 1.12.4; vendored Highcharts adapter patched `.bind`/`.unbind` → `.on`/`.off`); both CI security gates made blocking; new `assets` CI job precompiles and boots with a manifest present | `bbdd4b4` |
| — | **Boot regression introduced by the 8.1 upgrade**: the `json ~> 3.1` pin broke sprockets 3.7.5, which calls `JSON.parse(obj, create_additions: false)` in its manifest reader, so the app could not boot when a compiled manifest already existed. CI missed it because a fresh checkout has no manifest and `rake test` never reads one. `json` restored to `~> 2.7`; sprockets 4 is not an escape hatch (identical call). | `bf1fd80` |
| §1.3 | bcrypt password hashes rendered into `users/index`, `users/show` and prefilled into the edit form (`text_field :password`) — missed by PR #4, which only fixed the JSON API. Also a functional bug: resubmitting the edit form re-hashed the hash and locked the account out. | `365c845` |
| — | `User#right_names` memo survived `reload`, so a reloaded user reported stale rights | `5ab2ca4` |
| §4.3 | Request coverage for `role_add`/`role_remove` escalation and `acknowledge`/`ackall` | `854f641` |
| §4.3 (2b) | `acknowledge`/`ackall` converted from GET to POST, so `protect_from_forgery` covers a state-changing action | `60aedf6` |
| §4.1-A | Subprocess coverage of the checkpoint/claim/reclaim machinery: crash mid-file, resume at the offset, no duplicate rows, `.processing` reclaimed | `94654d1` |
| §5.3 | A `StandardError` line is now logged, counted, and skipped instead of `exit 1`-ing the importer; `puts` → `Rails.logger` + stdout broadcast for the journal | `c5d82ab` |
| §5.1 | `provision.sh` made idempotent, `db/seeds.rb` idempotent (plus a re-seed regression test), three systemd units, CI job validating both | `bf547e0` |
| §5.4 | MIT `LICENSE` | `68a6c39` |
| §5.5 | `README.md` rewritten as operator documentation; `README`/`README.rdoc` deleted | `58407e9` |
| §4.2 | `search`/`search_period` merged; `export_logs.rb` → `bin/`; `syslog.pl` global-scope bug, unchecked `open`, dead `$DEBUG`; 26 scaffold asset stubs deleted. Also a cucumber scenario that was passing for the wrong reason (a `0` time bound became the string `'0'` and matched everything) | `4ee7458` |
| — | The cross-version probe harness used to verify the upgrade is now in the repo (`script/probe.rb`, `script/probe_compare.rb`, `rake probe:run` / `probe:compare`). Committing it fixed a coverage hole: plain `:id` resolved to a literal `1`, so every member route 404'd and show/edit/roles were never rendered — the §1.3 leak produced no probe diff at all. | `67566f4` |

The superseded review revisions -- including the misdiagnoses and the reasoning
that corrected them -- are preserved in git:

```
git show 104abd4:RECOMMENDATIONS.md   # through old §7, at the retention merge
git show b759c51:RECOMMENDATIONS.md   # adds old §7.1–7.5, the merge regressions
```

---

*This review was produced by an AI agent (OpenHands) on behalf of the user.*
