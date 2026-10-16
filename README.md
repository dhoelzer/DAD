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
                     │   runs Job rows whose next_run has passed    │
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
- **PostgreSQL** for production. Development and test use SQLite, so the test
  suite needs no database server.
- Apache + Phusion Passenger for the web UI (what `provision.sh` configures).

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

Two deliberate behaviours:

- **It fails closed.** If the filesystem cannot be measured, nothing is deleted —
  a bogus reading must not delete history. The job logs and reports it instead.
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

On SQLite there is no partitioning, so none of this applies; the job reports
`event partitioning is Postgres-only; nothing to do`.

---

## Development

```bash
bundle exec rake test          # unit + controller tests (SQLite, no server needed)
bundle exec cucumber           # feature tests
bundle exec brakeman -q        # static analysis, must report 0 warnings
bundle exec bundle-audit check # dependency CVEs
```

CI runs the unit tests and cucumber features on **both SQLite and Postgres**,
plus brakeman, bundle-audit, an asset-precompile job, and a job that checks
`provision.sh` parses and the systemd units verify. The Postgres job exists
because the SQLite suite cannot see adapter-specific SQL breakage, and it has
caught total failures before. See `.github/workflows/ci.yml`.

To run the suite against Postgres locally:

```bash
createuser dad && createdb -O dad dad_test
DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test bundle exec rake db:migrate_from_scratch
DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test bundle exec rake test
DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test bundle exec cucumber
```

Without `DATABASE_URL` everything runs on SQLite, and the partitioning and backup
tests skip rather than fail.

Before deploying a change to the ingest path, read the comments in
`app/models/event.rb` around `storeEvent` / `flush_and_wait` and
`lib/log_queue.rb`. The checkpoint and the batch flush are coupled, and getting
the ordering wrong either loses rows or duplicates them.

---

## License

MIT — see [LICENSE](LICENSE).
