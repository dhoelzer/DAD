# DAD — Open Recommendations

Scanned at `b6adf25` (2026-10-14), after PRs #1–#19 all merged.

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
| Test suite | Green: 157 runs / 457 assertions, 4 cucumber scenarios — but shallow on CRUD (§4.3) |
| Broken admin screens | **Open — 4 live defects (§2.1)** |
| Poison line / observability | **Open — was mis-marked as fixed (§5.3)** |
| Rails 4.2 EOL, CI security gates | Open (§5.2, §1.2) |
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

Brakeman reports **3 warnings** today (2 high confidence, 1 medium) and
bundle-audit reports open CVEs against the Rails 4.2 line. The comment in the
workflow says to flip these after the Rails upgrade — which is reasonable, but
nothing currently tracks that, and the Rails upgrade is unscheduled (§5.2).

**Fix:** split the job. Make **brakeman blocking now** (the 3 warnings are
pre-existing and can be baselined with `--combine-branches` or an ignore file, so
blocking does not stall PRs); leave bundle-audit advisory until Rails is
supported, since those CVEs are unfixable on 4.2 and blocking on them is noise.

---

## 2. Correctness

### 2.1 🔴 Four admin screens are broken, and none is covered by a test **[correctness]**

Each was verified still present at `b6adf25`. Each is reachable by a single
request, and none is exercised by the suite — `test/controllers/` contains no
`sessions_controller_test.rb` or `users_controller_test.rb`, and
`jobs_controller_test.rb` never hits the `test` action.

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | `SessionsController#create`/`#update` raise on every real submission | `session_params` permits `:hash`; the column is `session_hash`. ActiveRecord raises `UnknownAttributeError` rather than ignoring the unknown key | Permit `:session_hash` |
| 2 | `JobsController#test` 500s as routed | `before_action :set_job, only: [:show, :edit, :update, :destroy]` — `@job` is nil when `test` reads `@job.script` | Add `:test` to the list, or delete the action and its route |
| 3 | `Users#destroy` does not revoke sessions | Body is just `@user.destroy`; Session rows stay live. `gatekeeper` slides `expiry` forward an hour on every request (`application_controller.rb:107`), so **an active deleted account keeps its login indefinitely** — it only expires if the user stops making requests for an hour | `Session.where(user_id:).each(&:destroy)` before destroying — `#do_logon` (`users_controller.rb:87`) already shows the pattern |
| 4 | `Users#update` can lock an account out | `@user.store_password(params[:user][:password])` runs unconditionally; omit the field and the password becomes a hash of `nil` | Guard on the param being present |

Defect 3 is the most serious: **deleting an account does not end its access**,
and because the session expiry slides on each request, an actively used session
survives indefinitely. Defect 4 is the most likely to bite a real operator,
because Rails' `form_for` edit forms commonly omit the password field.

**Do these with tests, not alone.** The reason all four survived is that no
request ever touched those routes. Fix #1 and #2 are one-word changes that will
stay fixed only once a request spec covers them.

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

### 3.1 The statistics helpers run the same query up to four times per dashboard render **[performance]**

`ApplicationHelper` has four methods that call `statistics_by_hour(0, since)` and
then reduce the same result set differently:

- `hourly_average` → mean
- `hourly_stats` → mean, variance, standard deviation
- `events_per_hour` → chart series
- `daily_insert_average` → mean of type 1, divided by 60

`System#hourly_stats` and `System#events_per_hour` are the same pattern over
`System.hourly_counts(self.id, since)`.

Each is a separate round trip returning the same rows. On a dashboard that polls
(`index.js.erb`), that is the same aggregate computed repeatedly.

**Fix:** one method returning the bucketed rows, with the reductions applied to
it in Ruby. `hourly_stats` already computes mean/variance/sd from `values`;
`hourly_average` is that same `values.mean`. This is a contained refactor with an
obvious test — assert one query where there are currently four.

*Correction:* an earlier revision of this document also listed
`system_service_stats` as an N+1. That method no longer exists. The three N+1s
that did exist — `system_stats`, `service_stats`,
`System.with_events_within_hours` — were fixed in PR #18 and verified at two
queries regardless of row count.

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

157 runs / 457 assertions across 41 test files, plus 4 cucumber scenarios. That
sounds substantial, and it caught real regressions during the ingest work — but
it covers no CRUD request path for `sessions`, `users`, or the `jobs#test`
action, which is exactly why the four defects in §2.1 survived.

The highest-value next tests are **request specs over the admin CRUD routes**,
not more unit tests of model helpers. They also make the §2.1 fixes durable.

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

### 5.2 Rails 4.2 is end-of-life **[operations]**

`Gemfile:7` pins `rails '~> 4.2.11'`. The 4.2 line has open CVEs with no fix
available, which is why bundle-audit is non-blocking (§1.2). Ruby is pinned to
2.7.8 in CI, also EOL.

This is the dependency that gates several other items: Postgres partitioning
(§3.2) and a Postgres test database (§4.1 option C) both become tractable during
a Rails upgrade, and the CI security gates can only be made blocking afterwards.

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

Still no license file. On GitHub that means all rights are reserved by default,
so downstream use is legally blocked. If DAD is meant to be open source, pick one
and add it.

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
| 1 | §2.1 four admin defects, **with request specs** | hours | Live data-integrity and access-control bugs; the tests are what keep them fixed |
| 2 | §1.1 production secret: rotate + secret scanning | hours | Impersonation risk if any deployment still uses the 2015 key |
| 3 | §4.3 CRUD request coverage | days | Prevents the §2.1 class of bug recurring |
| 4 | §1.2 make brakeman blocking (baselined) | hours | Cheap, stops new sinks landing |
| 5 | §3.1 statistics query duplication | hours | Contained, measurable, dashboard hot path |
| 6 | §4.1 option A: subprocess coverage of threaded ingest | hours | Nearly free — harness exists |
| 7 | §5.3 poison-line handling + `Rails.logger` | hours | Stops silent ingestion stalls; compounds §5.1 |
| 8 | §5.1 systemd units | days | The importer dying silently is the main operational risk |
| 9 | §5.2 Rails 5→7 | ongoing | Gates §3.2, §4.1-C, and blocking security gates |
| 10 | §3.2 partitioning, §3.3 FTS, §4.1-B `EventIngestor` | ongoing | Real work, but bounded by the above |
| 11 | §5.4 LICENSE, §5.5 README, §4.2 dead code | hours | Hygiene; do opportunistically |

**The pattern worth acting on.** Three separate findings in this review — the
importer that died at startup while CI stayed green, the four broken admin
screens, and the checkpoint bugs — have the same cause: nothing exercises the
entry points. The `__FILE__ == $PROGRAM_NAME` guard added in PR #16 and request
specs over the CRUD routes are the two structural fixes for it. Priorities 1, 3
and 6 are all versions of the same investment.

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

The superseded review revisions -- including the misdiagnoses and the reasoning
that corrected them -- are preserved in git:

```
git show 104abd4:RECOMMENDATIONS.md   # through old §7, at the retention merge
git show b759c51:RECOMMENDATIONS.md   # adds old §7.1–7.5, the merge regressions
```

---

*This review was produced by an AI agent (OpenHands) on behalf of the user.*
