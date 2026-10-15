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
                     │   Event.storeEvent per line → events + words │
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

## Ingest semantics, in one paragraph

The importer claims each file by renaming it to `<name>.processing` before
reading, and checkpoints a byte offset in a sidecar once that batch's rows are
committed. A crash mid-file leaves the `.processing` file, and the next pass
reclaims it and resumes at the offset rather than re-inserting rows. A line that
raises `StandardError` is logged at warn, counted, and skipped — one bad record
no longer wedges the pipeline, which it used to, permanently. Anything that is
not a `StandardError` still stops the run and rewinds the checkpoint, because
those errors invalidate the whole pass. Skipped lines are recorded as a
`Statistic` series so a rising failure rate is visible instead of silent.

---

## Development

```bash
bundle exec rake test          # unit + controller tests (SQLite, no server needed)
bundle exec cucumber           # feature tests
bundle exec brakeman -q        # static analysis, must report 0 warnings
bundle exec bundle-audit check # dependency CVEs
```

CI runs all four, plus an asset-precompile job and a job that checks
`provision.sh` parses and the systemd units verify. See `.github/workflows/ci.yml`.

Before deploying a change to the ingest path, read the comments in
`app/models/event.rb` around `storeEvent` / `flush_and_wait` and
`lib/log_queue.rb`. The checkpoint and the batch flush are coupled, and getting
the ordering wrong either loses rows or duplicates them.

---

## License

MIT — see [LICENSE](LICENSE).
