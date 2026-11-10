# DAD — Log Analytics

DAD ingests syslog, indexes every word, and gives you a web UI for searching the
corpus, alerting on patterns, and running scheduled jobs against it.

It is a Rails application plus two long-running Ruby processes and one Perl
collector. The web UI is the least important part: if the importer is down, you
have a search engine over nothing.

---

## How the pieces fit together

```
                     ┌──────────────────────────────────────────────┐
 syslog/UDP:514 ───► │ syslog.pl          (dad-syslog)              │
                     │   writes Logs/LogStaging/syslog.<epoch>      │
                     │   renames it to Logs/LogsToProcess every 60s │
                     └──────────────────────────────────────────────┘
                                        │
                     ┌──────────────────▼───────────────────────────┐
                     │ import_syslog.rb   (dad-importer)            │
                     │   claims each file (.processing sidecar)     │
                     │  EventIngestor.storeEvent → events + words   │
                     │   moves the file to Logs/ProcessedLogs       │
                     │   purges ProcessedLogs older than 7 days     │
                     └──────────────────┬───────────────────────────┘
                                        │  PostgreSQL
                     ┌──────────────────▼───────────────────────────┐
                     │ Rails app (Passenger/Apache)                 │
                     │   search, alerts, dashboards, users/roles    │
                     │                                              │
                     │ scheduler.rb       (dad-scheduler)           │
                     │   runs due Job rows through a fixed handler  │
                     │   registry — no user-authored code is run    │
                     └──────────────────────────────────────────────┘
```

Three processes, three systemd units, one database. The `Logs/` directory is the
handoff: the collector writes it, the importer consumes it, and nothing else
should touch it.

| unit | runs | loop |
|---|---|---|
| `dad-syslog` | `syslog.pl` | rotates the staging file every 60s |
| `dad-importer` | `import_syslog.rb` | one pass every 60s; purge every 12h |
| `dad-scheduler` | `scheduler.rb` | due `Job` rows every 60s |

---

## Requirements

- Ruby **3.3.8** (`.ruby-version`)
- Rails **8.1** (installed via Bundler)
- **PostgreSQL** for production. Development and test can use SQLite, in which
  case the test suite needs no database server.
- Apache + Phusion Passenger for the web UI (what `provision.sh` configures).
- **Docker + Compose** if you want the whole stack, or the test suite against
  Postgres, without installing any of the above. See
  [The Docker Compose way](#the-docker-compose-way).

---

## Configuration

### Environment variables

Production reads its configuration from the environment. Set **either**
`DATABASE_URL` **or** the individual `DAD_DB_*` variables.

If `DATABASE_URL` is set, Rails uses it and the `DAD_DB_*` variables are ignored
for the connection — verified, not assumed: with both set, the app connects to
the URL's database. The individual variables exist so you can point at a cluster
without hand-writing a URL, since `config/database.yml` interpolates them.

| variable | required | used by | notes |
|---|---|---|---|
| `SECRET_KEY_BASE` | **yes** (production) | Rails | Session cookie signing. Without it Rails refuses to boot. |
| `DATABASE_URL` | one of these two | Rails / `config/database.yml` | e.g. `postgres://rails:pw@127.0.0.1/events_prod`. Takes precedence when set. |
| `DAD_DB_USER` / `DAD_DB_PASSWORD` / `DAD_DB_NAME` / `DAD_DB_HOST` | ↑ | `config/database.yml` | Used only when `DATABASE_URL` is unset. `DAD_DB_NAME` defaults to `events_prod`, `DAD_DB_HOST` to `127.0.0.1`. |
| `DAD_ADMIN_USER` | no | `db/seeds.rb` | Defaults to `admin`. |
| `DAD_ADMIN_PASSWORD` | **yes** to seed | `db/seeds.rb` | Seeding raises rather than creating a well-known default account. |
| `DAD_EVENT_RETENTION_DAYS` | no | `EventPartitioning` | Postgres only. How many days of event history retention keeps. **Default 365.** `0` or negative keeps every partition. A floor, not an exact age: a month is only dropped once the whole month is past the cutoff. |
| `DAD_OFFLINE_STORAGE_DIR` | no | `EventPartitionBackup` | Where a month's CSV archive is written before its partition is dropped. Absolute, or relative to the app root. Default `offline_storage` under the app root; `provision.sh` sets `/var/DAD/offline_storage`. |

`RAILS_ENV` is set by the units and by `provision.sh`; you rarely set it by hand.

### Where the secrets live

`provision.sh` generates the passwords and the signing key once and writes them
to two root-owned files, mode `0600`, never committed:

- `/etc/DAD/environment` — shell form (`export KEY=value`), for humans and for
  anything that sources it.
- `/etc/DAD/environment.d/dad.conf` — systemd form (`KEY=value`), read by the
  three units' `EnvironmentFile`.

They are separate files because **systemd has no shell**. Pointing
`EnvironmentFile` at the `export`-style file makes systemd parse the literal
string `export SECRET_KEY_BASE` as a variable name, so every value arrives empty
and Rails boots with a nil `secret_key_base`. If you add a variable, add it to
both.

Re-running `provision.sh` reuses the existing values, so re-provisioning does not
invalidate sessions or rotate the database password out from under the app.

### Rotating the signing key

Because `provision.sh` only generates secrets on first run, use the separate
script to change `SECRET_KEY_BASE` on a host that is already provisioned:

```bash
sudo bin/rotate_secret_key_base
```

It writes a new key into both env files (keeping every other value), restarts
apache2 and the three `dad-*` services so Passenger stops holding the old value,
and leaves the previous env file at `/etc/DAD/environment.pre-rotation.<UTC>`.

Rotating does **not** log anyone out. Sessions are rows in the `sessions` table
looked up by token, not payloads signed with the key, so they survive a rotation
untouched. Only the Rails cookie session (`_Events_session`, which carries the
CSRF token and flash) is invalidated, and it is re-minted on the next request.

---

## Install

### The quick way (Vagrant)

```bash
vagrant up
```

`provision.sh` installs the packages, generates secrets, configures Apache +
Passenger, migrates, seeds, installs the three systemd units, and starts
everything. It is safe to re-run. The box is then reachable at
`192.168.155.15` (self-signed certificate), with the admin username and password
printed at the end of provisioning and stored in `/etc/DAD/environment`.

### The manual way

```bash
bundle install

# development / test use SQLite and need no configuration
bundle exec rake db:migrate
bundle exec rake test

# production
export SECRET_KEY_BASE=$(openssl rand -hex 64)
export DAD_DB_USER=... DAD_DB_PASSWORD=... DAD_DB_NAME=events_prod DAD_DB_HOST=127.0.0.1
export DAD_ADMIN_PASSWORD=$(openssl rand -hex 12)
bundle exec rake db:migrate RAILS_ENV=production
bundle exec rake db:seed RAILS_ENV=production
bundle exec rake assets:precompile RAILS_ENV=production
```

`db:seed` is idempotent — it creates the five rights, the two roles, and the
admin user, and re-running it changes nothing. It deliberately does **not** reset
an admin password that has been changed since.

### The Docker Compose way

The whole stack — the app in its own containers, PostgreSQL in a separate one:

```bash
docker compose up --build
```

Then browse to <http://localhost:3000> and sign in as **`admin` /
`dad_dev_password`**. Override it with `DAD_ADMIN_PASSWORD=... docker compose up`
if you care; that value exists only so the stack is usable out of the box, and
production takes its password from `provision.sh`.

`docker compose up` runs a one-shot `migrate` service first. On an empty database
it builds the Postgres schema from `db/migrate` and seeds the roles, rights and
admin user; on every later start it does plain `db:migrate` and leaves your data
alone. Without the seed the stack comes up with zero users, and the login form
renders fine but can never succeed.

| service | runs | equivalent systemd unit |
|---|---|---|
| `db` | PostgreSQL 17, data in the `pgdata` volume | — |
| `migrate` | `rake db:create` + migrate, then exits | `provision.sh` |
| `web` | `rails server` on :3000 | Apache + Passenger |
| `importer` | `import_syslog.rb` | `dad-importer` |
| `scheduler` | `scheduler.rb` | `dad-scheduler` |
| `syslog` | `syslog.pl`, UDP :514 | `dad-syslog` |
| `test` | the suite, on Postgres (`--profile test`) | the CI `postgres` job |

The service split mirrors production deliberately: these are independent
long-lived processes with different failure modes, and the repo already ships a
unit for each. One container running all three under a supervisor would hide
exactly the coupling those units exist to fix.

```bash
docker compose logs -f importer
docker compose exec db psql -U dad dad_development
docker compose down          # keep the volumes
docker compose down -v       # discard the database too
```

Two things worth knowing before you reach for it:

- **The database port is not published.** The app containers reach `db` over the
  Compose network by service name, and publishing 5432 by default collides with a
  Postgres already running on your machine. For host access, use the override:
  `docker compose -f docker-compose.yml -f docker-compose.db-port.yml up`
- **Code is baked into the image, not bind-mounted.** The image runs as uid 1000;
  mounting a checkout owned by a different uid makes Rails' `log/` and `tmp/`
  writes fail with `EACCES` in a way that reads like an app bug. The gem layer is
  cached, so after an edit `docker compose up --build` only re-runs `COPY . .`.

The image's `WORKDIR` is `/var/DAD`, not `/app`, because `syslog.pl` hardcodes
absolute paths under `/var/DAD/Logs` and every systemd unit sets
`WorkingDirectory=/var/DAD`. Any other `WORKDIR` and the collector writes into a
directory the importer never reads.

This is the development and test path. Production still deploys through
`provision.sh` + systemd + Apache/Passenger.

### Running the three processes by hand

Useful for development; in production use the units (see `systemd/README.md`).

```bash
perl syslog.pl &                    # needs root or CAP_NET_BIND_SERVICE for :514
ruby import_syslog.rb &             # chdir's into Logs/LogsToProcess itself
ruby scheduler.rb &
```

Ctrl-C behaviour differs, and it matters when you stop the importer by hand:

- `import_syslog.rb` rescues `Interrupt` mid-pass, flushes the in-memory batch,
  and re-raises. Nothing already parsed is lost, and the file stays claimed with
  its checkpoint behind the last committed row, so the next pass resumes there.
- `scheduler.rb` has no interrupt handling. It is a 60-second loop with no
  in-memory state between iterations, so stopping it is safe — but it will not
  finish a job it is part-way through.

---

## Logs

Two places, and the distinction matters when something is broken:

1. **Rails' own log** — `log/production.log` (or `development.log`, `test.log`).
   Full detail, written by `Rails.logger`.
2. **The journal** — when run as a service, both daemons broadcast `Rails.logger`
   to stdout as well, so `journalctl -u dad-importer` shows the same lines with
   severity and timestamps intact. A daemon that is silent in the journal looks
   hung, which is why the broadcast exists.

Do not use `puts` in these processes. Severity and timestamps are lost, and the
output does not reach the journal in a form you can filter.

The **ingested log files** are a third thing, not application logs:
`Logs/ProcessedLogs` is where ingested files go, and the importer deletes them
after `RETENTION_DAYS` (7). That directory is on the same disk as the live queue,
so if retention stops working the queue fills the disk. The importer logs
`Purged N from ...` every 12 hours; if you do not see that line, retention is not
running.

---

## Ingest semantics

The importer claims each file by renaming it to `<name>.processing` before
reading, and checkpoints a byte offset in a sidecar once that batch's rows are
committed. A crash mid-file leaves the `.processing` file, and the next pass
reclaims it and resumes at the offset rather than re-inserting rows. A line that
raises `StandardError` is logged at warn, counted, and skipped — one bad record
no longer wedges the pipeline, which it used to, permanently. Anything that is
not a `StandardError` still stops the run and rewinds the checkpoint, because
those errors invalidate the whole pass. Skipped lines are recorded as a
`Statistic` series so a rising failure rate is visible instead of silent.

Ingest is **at-least-once, not exactly-once**. A crash with a batch still in
flight re-reads that batch, so some events can be duplicated. The guarantee is
asymmetric: the checkpoint only advances once a batch's rows are durable, so a
crash never *loses* rows that were already committed, and with at most one writer
thread in flight it cannot duplicate more than one batch. One batch is not
necessarily small — in production it starts at 2000 lines and grows with
throughput, so the duplicate count can reach thousands.

The consequence for anyone reading the numbers: **duplicate events are possible
after a crash**, so anything that counts events — the dashboards, alert
thresholds, `Statistic` rates — is approximate across a crash boundary. This is a
deliberate trade-off, not a bug, and `test/import_syslog_crash_test.rb` pins both
halves: reclaim re-inserts nothing, and no line goes missing.

### Batching

Each flush writes one batch as a multi-row `INSERT`. A batch is chunked into as
many statements as the database's limit on bind parameters per statement requires
(32,766 on SQLite, 65,535 on Postgres), and the chunks commit in a single
transaction — so a batch is still all-or-nothing, and a failed batch leaves no
index rows behind pointing at events that were never written.

That chunking is what makes the batch size safe to raise. The importer starts at
2000 lines in production and adjusts upward while throughput improves, with no
upper bound; before chunking, a batch that large produced a statement over the
parameter limit and the flush failed outright with `too many SQL variables`.
Batch size is now bounded by memory and by how much you are willing to duplicate
after a crash, not by the database.

### Word resolution

New words are resolved in bulk, once per batch, rather than one at a time as each
line is parsed. A token already in the ingest word cache is stamped and indexed
immediately; a token that is not is held until the batch is flushed, at which
point the whole batch's unknown tokens are resolved together — one indexed lookup
for the words that already exist and one bulk insert for the rest.

This is the single largest factor in ingest throughput. On 20,000 realistic syslog
lines containing 46,450 distinct words, the old per-token path issued 186,089
statements and 46,450 separate transactions; the batched path issues 360 and 67.
Measured end to end: **6.4×** faster on a cold `words` table (a first run or a
backfill) and **2.36×** faster once `words` is already populated, which is the
steady state for a running collector.

Two things follow from this that are worth knowing. First, the `events_words` rows
written are identical either way — the change is invisible to search, and the
index is not a trade-off being made for speed. Second, a word that appears for the
first time is only written to the `words` table when its batch is flushed, so on a
crash it is re-read with the rest of that batch rather than lost; this is the same
at-least-once boundary described above, not a new one.

If you are sizing a backfill, the cold-cache figure is the relevant one; if you are
sizing steady-state collection, use the warm figure.

---

## Search, displays, and exclusions

**Search is a word index, not a substring index.** Ingest tokenises every line on
whitespace into `words` and links them to events through `events_words`
(`EventIngestor.storeEvent`). Before tokenising, the line is downcased and every
character outside `a-z A-Z 0-9 space - _ : @ * / .` is replaced with a space, so
indexed words contain only lowercase letters, digits, and `- _ : @ * / .`
(`events.hunks` still holds the original line, untouched).

`Event.search` splits the query on whitespace, downcases it, and returns events
that match **every** term, where a term matches if it is a literal **prefix** of an
indexed word. So `sshd` finds `sshd:` and `sshd2`, but `fail` does not find
`unfail`. `%` and `_` in a term are escaped to literals. A term containing any other
punctuation — `=`, `"`, `#`, `,` — can never match, because that character is not
in any indexed word; it was a word separator on ingest. Word text is also truncated
at 255 characters, so very long tokens collide on the truncated form.

Results are paged with `offset`/`limit` and ordered oldest-first. The time window
is required — a search over all history is not a thing the index can answer
cheaply.

Leaving **Timeframe Search** unticked searches the relative window from the
*Timeframe* dropdown. Ticking it searches the absolute start/end range instead; if
those fields cannot be read, the result line says so rather than quietly answering
a different question.

**Displays** reformat matching events for the event views. A Display is a `key`
regex plus a `display_script` written in a small line-oriented directive
language, which is *parsed, never evaluated* — you cannot put Ruby in a display
filter, and the form says so:

```
fields 1,2,5        # emit these 1-based positional fields, in this order
regex PATTERN       # emit PATTERN's capture groups instead of positions
label 3=proto:      # prefix the 3rd emitted token with "proto:"
join ,              # join emitted tokens with this separator (default: space)
```

`#` starts a comment. A malformed spec is rejected on save
(`DisplayRule.validate`); at render time it degrades to the raw line rather than
breaking the page.

**Exclusions** only affect the live dashboard feed. `Event.recent_events` drops
lines matching the union of every Exclusion pattern, and patterns are matched
**literally** (`Regexp.union` escapes metacharacters), so `sshd.*fail` matches
those seven characters, not a regex. Blank patterns are ignored — a blank pattern
would otherwise empty the feed for every user. Exclusions do not affect stored
data or search results.

---

## Retention and partition archives

On Postgres, `events` and `events_words` are range-partitioned by month, and
retention drops a month by `DROP TABLE`-ing its partition — metadata-only, so it
costs the same whether the month holds 10k rows or 100M, where `DELETE` would
rewrite every index. The `maintain_event_partitions` job (seeded daily) creates
coming months and drops expired ones.

**A month is only dropped once it has been archived.** Before any drop,
`EventPartitionBackup` writes the partition to a CSV under
`DAD_OFFLINE_STORAGE_DIR` (default `offline_storage` under the app root;
`provision.sh` uses `/var/DAD/offline_storage`, mode `0700`, owned by the service
user). If the archive does not complete, the partition is **kept** and the next
run retries. That is the whole safety property: retention cannot destroy the only
copy of a month's rows.

Retention keeps `DAD_EVENT_RETENTION_DAYS` days of history, **default 365**. It is
a floor, not an exact age — a partition is dropped only once its whole month is
past the cutoff, so rows can survive up to a month longer. Set it to `0` to keep
everything.

Archives are plain CSV with a header row, so they are readable with any tool. To
put a month back:

```bash
bin/restore_event_partition --list                    # what is archived
bin/restore_event_partition events_p202509            # recreate + load
```

The restore recreates the partition with the same `FOR VALUES` range the
maintenance job would have used, then loads the CSV by `COPY`. It refuses to run
if the partition already exists.

Separately, `bin/export_logs` streams every stored event back out as its original
log line, one per stdout line, for replaying the corpus into another system. It
pages by primary key, so it is safe on a table too large to hold in memory.

### Archive retention (free-space floor)

Archives are never pruned unless an admin says they may be. Set a **required free
space percentage** for the partition holding them under **Preferences →
"Archive partition: required free space (%)"** (Admin-only). Blank or `0` leaves
pruning off.

With a floor set, the `maintain_event_partitions` job deletes whole months of
archives — **oldest first** — whenever the archives on disk, plus what the next
archives are expected to need, would breach it. Pruning happens *before* any new
archive is written, so the disk never fills mid-dump. The size of the incoming
archives is measured from the partitions themselves (`pg_relation_size`, rows
only — indexes are not in the CSV), falling back to the size of the largest
recent archive when it cannot be.

**Pruning is unrecoverable.** An archive is usually the only copy of a month the
database has already dropped; deleting it destroys that history for good.

```bash
bin/prune_event_archives --check      # floor, usage, and what is stored
bin/prune_event_archives --dry-run    # exactly what would be deleted
bin/prune_event_archives              # delete it
```

Three deliberate behaviours:

- **It fails closed.** If the filesystem cannot be measured, nothing is deleted —
  a bogus reading must not delete history. The job logs and reports it instead.
- **It never prunes an archive it is about to rewrite.** The scheduled job skips
  archives whose partition is still in the database and due to be archived this
  run: deleting one would free space that the very next step spends writing it
  again, so the run would report success and still breach the floor. The manual
  `bin/prune_event_archives` has no such pending write, so it treats every
  archive as prunable.
- **It alerts when the floor cannot be met.** If every archive has been deleted
  and the floor still fails, a Critical alert is raised (once, not per run).
  That is the state where retention is about to stop working for lack of space.

Two things to watch:

- **Disk.** If the archive directory fills, archiving fails and partitions stop
  being dropped — the database grows instead of the disk filling. Set a floor, or
  check the job output: it reports `N expired partition(s) kept pending archive`
  when this is happening.
- **Secrets.** Archives are raw log lines. Anything that ever reached a log line
  is in them, so treat the directory as sensitive: it is `0700` for a reason.

The `disk_utilization` job reports the partition holding the archives, not the
root filesystem, and names the directory it measured. If that partition cannot be
measured it says `disk utilization unknown` rather than `0%` — a missing reading
must not look like an empty disk.

On SQLite there is no partitioning, so none of this applies; the job reports
`event partitioning is Postgres-only; nothing to do`.

---

## Jobs

A `Job` is a row the scheduler re-runs every `frequency` seconds once `next_run`
is in the past. Creating one means **choosing an operation from a fixed list** in
the Jobs form; no Ruby, shell command, or other user-authored code is stored or
executed anywhere. `JobHandler::HANDLERS` is the whole set:

| operation | what it does |
|---|---|
| `prune_words` | trims the importer's in-memory word cache and re-tunes its lifetime |
| `reset_caches` | clears the importer's class-level caches (needed after a DB rollback) |
| `reset_stats` | resets the throughput clock behind the EPS chart |
| `disk_utilization` | reports usage of the partition holding the event archives |
| `maintain_event_partitions` | creates next month's partitions, archives and drops expired ones (Postgres only; seeded daily) |
| `tune_dashboard_feed` | persists the self-tuned live-feed size (seeded hourly) |
| `prune_sessions` | reclaims login sessions whose expiry has passed (seeded hourly) |

Adding a capability means adding an entry to `JobHandler::HANDLERS` and
deploying — it is deliberately not something an operator can do from the web UI.
`Job` validation rejects a `script` that is not a registered name, and
`JobHandler.perform` raises `UnknownHandler` rather than falling back to
`eval`.

A failing job is rescued, raises a **Critical** alert, and is still rescheduled —
so a permanently broken Job raises an alert on every cycle forever. Fix or delete
the Job rather than ignoring the alert.

A Job whose `frequency` is unusable (blank, zero or negative) is treated
differently, because rescheduling it is what used to crash the scheduler: it
raises a **Critical** alert and sets `next_run` to NULL, which disables it. It
will not run again until an operator puts a positive interval in the Jobs form.
That is deliberate — a row that cannot be scheduled should stop, not restart the
service every 60 seconds. `frequency` is validated on save and constrained in the
database, so this mainly catches rows written before the constraint existed.

Migration `20261014000001` cleared the `script` and `next_run` of every Job row
written under the old `eval` design, because that Ruby cannot be translated into
a handler name and the scheduler would otherwise alert forever. An operator who
still wants one of those tasks re-creates it by choosing a registered handler.

---

## Access control

Authorization is one fail-closed filter: `ApplicationController::CONTROLLER_RIGHTS`
maps each controller to the rights that may reach it, and a controller missing
from that map is unreachable to everyone. The five rights and what they unlock:

| right | grants |
|---|---|
| `Admin` | everything, including users, roles, rights, sessions, preferences, services, statistics |
| `Viewer` | events, alerts, searches, systems |
| `Commentator` | commenting on alerts, and Exclusions |
| `Taskmaster` | the Jobs screens |
| `Detective` | Displays and stored Searches |

Two roles are seeded: **Administrators** (`Admin` only) and **Analyst** (the other
four). Logon locks an account after 4 failed attempts and resets the counter after
5 minutes.

Login state is **not** a signed cookie. `gatekeeper` reads `cookies[:sessionID]`,
a `SecureRandom.hex(32)` token looked up in the `sessions` table, and refreshes
its expiry to +1 hour on each request. Consequences worth knowing: leaking
`SECRET_KEY_BASE` defeats CSRF protection but does **not** impersonate anyone, and
rotating it logs nobody out (sessions are rows, not payloads) — see
"Rotating the signing key" above.

A row is deleted when its token is presented after expiry, when the same user
logs in again, and by `Session.purge_expired`, which runs on logon and through
the seeded `prune_sessions` Job. The last two matter because a browser that was
closed never presents its token again, and that lookup is indexed on
`session_hash` — it runs on every authenticated request.

Admin list screens (users, sessions, jobs, roles, rights, preferences, comments,
exclusions, searches, displays, systems, statistics) are paginated at 25 rows per
page; `?page=N` selects one. Nothing in the UI loads a whole table.

---

## Development

```bash
bin/docker-test              # the suite on Postgres, in Docker -- preferred
bundle exec rake test        # unit + controller tests on SQLite, no server needed
bundle exec cucumber         # feature tests on SQLite
bundle exec brakeman -q      # static analysis, must report 0 warnings
bundle exec bundle-audit check # dependency CVEs
```

**Test on Postgres.** SQLite is still supported for a fast local loop, but it is
not the engine production runs, and the difference has shipped breakage before:
`Event.insertStatement` once emitted SQLite `?` placeholders through
`exec_query`, Postgres rejected them outright, and production could not insert a
single event while every SQLite job stayed green (RECOMMENDATIONS 3.2).
`events` and `events_words` are partitioned on Postgres and are not partitionable
on SQLite at all, so the SQLite suite never exercises the shape production
queries; the composite covering index on `events_words` is Postgres-only too.

`bin/docker-test` runs both suites against the Compose `db` service and then makes
the same two assertions the CI `postgres` job makes — that `events` and
`events_words` really are partitioned, and that no index was left `INVALID` by a
failed `CONCURRENTLY` build. It passes extra arguments through to the container,
so `bin/docker-test bundle exec rails test test/models/event_test.rb` runs one
file, and `bin/docker-test bash` drops you into it.

CI runs six jobs (`.github/workflows/ci.yml`): the unit tests and cucumber
features on **both SQLite and Postgres**, an asset-precompile job, a job that
checks `provision.sh` parses and the systemd units verify, a `security` job
(brakeman, bundle-audit, gitleaks), and a **`docker` job that builds this image
and boots the stack**.

The `docker` job is the one that would have caught the broken `Dockerfile.dev`.
Beyond building, it drives the running stack: it asserts the `migrate` service
left a partitioned `events`/`events_words` and at least one user, that the login
page actually renders (checking the body for "Could not find a JavaScript
runtime", so a missing runtime names itself instead of showing as a bare 500),
that an asset path the page emitted returns 200, and that a UDP packet sent to
`syslog`:514 ends up as a row in `events`. That last check is the only automated
test of the Perl collector — no Ruby-level job would notice it failing to start.

To run against Postgres without Docker, point `DATABASE_URL` at a local cluster.
Use `db:migrate_from_scratch`, not `db:migrate`: the committed `db/schema.rb` is
SQLite-flavoured, and `db:migrate` loads that dump into an empty Postgres database
and skips `db/migrate` entirely, so the partitioned shape is never built.

```bash
createuser dad && createdb -O dad dad_test
export DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test
bundle exec rake db:migrate_from_scratch
bundle exec rake test
bundle exec cucumber
```

Without `DATABASE_URL` everything runs on SQLite, and the Postgres-only
partitioning, backup and index tests skip rather than fail — which is the trap:
a green SQLite run says nothing about the partitioned path.

Before deploying a change to the ingest path, read the comments in
`app/models/event.rb` around `storeEvent` / `flush_and_wait` and
`lib/log_queue.rb`. The checkpoint and the batch flush are coupled, and getting
the ordering wrong either loses rows or duplicates them.

---

## License

MIT — see [LICENSE](LICENSE).
