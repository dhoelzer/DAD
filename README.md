# DAD — Log Analytics

DAD ingests syslog, indexes every word, and gives you a web UI for searching the
corpus, alerting on patterns, and running scheduled jobs against it.

It is a Rails application plus two long-running Ruby processes and one Rust
collector. The web UI is the least important part: if the importer is down, you
have a search engine over nothing.

---

## How the pieces fit together

```
                     ┌──────────────────────────────────────────────┐
 syslog/UDP:514 ───► │ syslog_collector   (dad-syslog)              │
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
| `dad-syslog` | `syslog_collector` (Rust) | rotates the staging file every 60s |
| `dad-importer` | `import_syslog.rb` | one pass every 60s; purge every 12h |
| `dad-scheduler` | `scheduler.rb` | due `Job` rows every 60s |
| `dad-windows` | `import_windows_events.rb` | optional; tails OpenWEC output every 10s |

Windows events are optional, and there are two ways to collect them. **DAD can
poll Windows hosts itself over WinRM** — that path needs no extra process,
because the poller runs as a `Job` inside `dad-scheduler`. The older path has
OpenWEC collect and a fourth process forward what it wrote. Both feed the **same**
`LogsToProcess` queue rather than a second importer — see
[Ingesting Windows events](#ingesting-windows-events).

---

## Requirements

- Ruby **3.3.8** (`.ruby-version`)
- Rails **8.1** (installed via Bundler)
- **PostgreSQL 17** for every environment, including development and test.
  SQLite is not supported: it cannot partition `events`/`events_words`, so a
  SQLite suite never exercises the shape production queries (see
  [Development](#development)).
- Apache + Phusion Passenger for the web UI, if you deploy by hand.
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
| `DAD_OFFLINE_STORAGE_DIR` | no | `EventPartitionBackup` | Where a month's CSV archive is written before its partition is dropped. Absolute, or relative to the app root. Default `offline_storage` under the app root; no unit sets it, but `WorkingDirectory=/var/DAD` makes that resolve to `/var/DAD/offline_storage` under systemd. |
| `DAD_AR_ENCRYPTION_KEY` | **yes** (production) | `WindowsTarget`, `ActiveDirectoryConnection` | Active Record encryption key for stored WinRM and LDAP bind passwords. 32 bytes, hex. Production refuses to boot without it. |
| `DAD_AR_ENCRYPTION_SALT` | **yes** (production) | `WindowsTarget` | Key-derivation salt for the same. Rails 8.1 requires it whenever encryption is configured. |
| `WINDOWS_SSL_VERIFY` | no | `WindowsPoll`, `AdQuery` | `none` trusts an internal CA's WinRM or LDAPS certificate instead of the system trust store. Set it deliberately; the default verifies. |
| `DAD_SYSLOG_SELF_HOST` | no | `SyslogSource` | `none` stops the importer naming a System after the container tag when the line arrives from this host's own bridge gateway. Default `auto`. See "Which host an event belongs to". |

`RAILS_ENV` is set by the systemd units and by Compose; you rarely set it by hand.

### Where the secrets live

On a systemd host, keep the passwords and the signing key in two root-owned
files, mode `0600`, never committed. Generate them once and reuse them; do not
regenerate on every deploy:

- `/etc/DAD/environment` — shell form (`export KEY=value`), for humans and for
  anything that sources it.
- `/etc/DAD/environment.d/dad.conf` — systemd form (`KEY=value`), read by the
  three units' `EnvironmentFile`.

They are separate files because **systemd has no shell**. Pointing
`EnvironmentFile` at the `export`-style file makes systemd parse the literal
string `export SECRET_KEY_BASE` as a variable name, so every value arrives empty
and Rails boots with a nil `secret_key_base`. If you add a variable, add it to
both.

Generate each value once and keep it. Re-generating the signing key on every
deploy invalidates every Rails session cookie, and re-drawing the database
password mid-deploy stops the app from connecting at all.

### Rotating the signing key

To change `SECRET_KEY_BASE` on a host that is already running:

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

### The Windows credential keys

`DAD_AR_ENCRYPTION_KEY` and `DAD_AR_ENCRYPTION_SALT` encrypt the WinRM passwords
that [polling Windows hosts](#polling-windows-hosts-directly) stores. Unlike the
signing key, **rotating them makes every stored Windows credential unreadable** —
there is no re-derivation path, so each host's password has to be re-entered in
the UI afterwards. Generate them once, put them in both env files, and keep them
off the rotation tooling.

---

## Install

The Docker Compose path below is the recommended one for development: it needs
no PostgreSQL install and no secret setup. The manual path is for a host where
you are standing up the systemd deployment yourself.

### The manual way

You need a PostgreSQL cluster reachable by the app, in every environment.

```bash
bundle install

# development
createuser dad && createdb -O dad dad_development
export DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_development
bundle exec rake db:migrate_from_scratch

# test
createdb -O dad dad_test
export DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test
bundle exec rake db:migrate_from_scratch
bundle exec rake test
bundle exec rake test:system

# production
export SECRET_KEY_BASE=$(openssl rand -hex 64)
export DAD_DB_USER=... DAD_DB_PASSWORD=... DAD_DB_NAME=events_prod DAD_DB_HOST=127.0.0.1
export DAD_ADMIN_PASSWORD=$(openssl rand -hex 12)
bundle exec rake db:migrate_from_scratch RAILS_ENV=production
bundle exec rake db:seed RAILS_ENV=production
bundle exec rake assets:precompile RAILS_ENV=production
```

Use `db:migrate_from_scratch`, not `db:migrate`, on an empty database: the
committed `db/schema.rb` is a portable dump that cannot express `PARTITION BY`,
and `db:migrate` loads that dump and skips `db/migrate` entirely, so the
partitioned shape is never built. See [Development](#development).

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
if you care; that value exists only so the stack is usable out of the box, and a
production deployment takes its password from `DAD_ADMIN_PASSWORD`.

`docker compose up` runs a one-shot `migrate` service first. On an empty database
it builds the Postgres schema from `db/migrate` and seeds the roles, rights and
admin user; on every later start it does plain `db:migrate` and leaves your data
alone. Without the seed the stack comes up with zero users, and the login form
renders fine but can never succeed.

| service | runs | equivalent systemd unit |
|---|---|---|
| `db` | PostgreSQL 17, data in the `pgdata` volume | — |
| `migrate` | `rake db:create` + migrate, then exits | the deploy's migrate step |
| `web` | `rails server` on :3000 | Apache + Passenger |
| `importer` | `import_syslog.rb` | `dad-importer` |
| `scheduler` | `scheduler.rb` | `dad-scheduler` |
| `syslog` | `syslog_collector`, UDP :514 | `dad-syslog` |
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

Three things worth knowing before you reach for it:

- **The database port is not published.** The app containers reach `db` over the
  Compose network by service name, and publishing 5432 by default collides with a
  Postgres already running on your machine. For host access, use the override:
  `docker compose -f docker-compose.yml -f docker-compose.db-port.yml up`
- **Code is baked into the image, not bind-mounted.** The image runs as uid 1000;
  mounting a checkout owned by a different uid makes Rails' `log/` and `tmp/`
  writes fail with `EACCES` in a way that reads like an app bug. The gem layer is
  cached, so after an edit `docker compose up --build` only re-runs `COPY . .`.
- **The stack watches itself.** Every service except `syslog` ships its own
  stdout and stderr to the collector, so a Rails stack trace or a Postgres
  checkpoint becomes an ordinary DAD event, filed under a Service named after the
  container (`dad-web`, `dad-db`, `dad-importer`, …). Search for your own errors
  the same way you search for anything else. If the host already holds UDP 514,
  `DAD_SYSLOG_PORT=1514 docker compose up` moves both the published port and the
  address every log driver sends to.
- **UDP 514 is published on every interface, on purpose.** The collector binds
  `0.0.0.0` and Compose publishes the port unmapped, because remote hosts sending
  their logs in is the point of the product. UDP syslog carries no authentication,
  so the control is network-level: restrict 514/udp at the firewall to the hosts
  you expect. Two different knobs, and neither is the fix:
  - Narrowing the **published mapping** to `127.0.0.1:514` would keep the stack's
    own logs arriving (the log drivers send from the host's loopback) but reject
    every remote host -- i.e. it silently disables the main use case.
  - Narrowing the **collector's own bind** would break even the stack's own logs:
    Docker delivers published-port traffic to the container's routable interface,
    not its loopback, so nothing would be accepted.

The image's `WORKDIR` is `/var/DAD`, not `/app`, because the collector hardcodes
absolute paths under `/var/DAD/Logs` and every systemd unit sets
`WorkingDirectory=/var/DAD`. Any other `WORKDIR` and the collector writes into a
directory the importer never reads.

This is the development and test path. Production deploys through the systemd
units in `systemd/` plus Apache/Passenger, with the secrets in
`/etc/DAD/environment` as described above.

### Running the three processes by hand

Useful for development; in production use the units (see `systemd/README.md`).

```bash
cargo build --release --manifest-path syslog_collector/Cargo.toml
./syslog_collector/target/release/syslog_collector &   # :514 needs root or CAP_NET_BIND_SERVICE
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

### Which host an event belongs to

Every staging line starts with the address the collector saw the packet come
from, and `EventIngestor` files that address as the `System`. That is right for a
host sending syslog directly, and wrong in the one deployment this project
recommends.

Under Docker, every container's log driver sends from the **bridge gateway**, so
`web`, `db`, `importer` and the rest all arrive carrying the same address and
collapse into a single System row labelled `(172.18.0.1)`. The container name —
the only host identity in the line — sits in the *application* slot, where the
log driver puts it:

```
172.18.0.1 Nov 13 15:14:49 dad-web[149784]: Started GET /users/logon
```

`SyslogSource` resolves the two slots structurally instead of positionally, and
the pid is the marker. In syslog the application is followed by its pid and a
colon, which after the parser's sanitizing pass is the token triple
`name` `digits` `:` — the brackets in `sshd[4242]:` are *spaces* by then, so
matching on `name[pid]:` would test a string the parser never sees. A hostname
slot has no pid after it, so whichever token owns the pid slot is the
application, and a token sitting in front of it is host information.

That one rule fixes a second, unrelated mis-parse. RFC 3164 as rsyslog forwards
it by default *does* carry a hostname slot:

```
10.0.0.5 Jun  1 12:00:00 web01 sshd[4242]: Accepted publickey for bob
```

The old positional read took `web01` as the Service — and the Service sanitizer
strips digits, so the row said `web` — and dropped `sshd` entirely. It now
records host `web01`, service `sshd`.

Renaming a System after the tag happens **only** when the source address is one
of this container's own default-route gateways, read from `/proc/net/route`, and
only when the importer is actually running in a container. Both conditions
matter: without them, a systemd deployment would rename any syslog that happened
to arrive from the LAN router — and routers do send syslog. A remote host's
address is its own identity and is never rewritten.

Set `DAD_SYSLOG_SELF_HOST=none` if something real does send from the bridge
address — the Docker host itself, or a VM behind the same bridge.

Two consequences worth knowing:

- The name goes in `systems.address`, not `systems.name`. `address` is what
  `System.find_or_add` keys identity on; `name` is an operator-assigned label.
- The pid in `dad-web[149784]` is **not** the container's process id. It is
  identical for every container on the host — measured, all five services
  reported `149784` — because it is `dockerd`'s. It carries no per-process
  information and is never used as an identity.

The Windows forwarder is unaffected: it emits `<host> <ISO-8601> <provider> …`
with no pid slot, so the fallback path applies and the host it states is kept.

### Batching

Each flush writes one batch as a multi-row `INSERT`. A batch is chunked into as
many statements as the database's limit on bind parameters per statement requires
(Postgres caps a statement at 65,535 parameters), and the chunks commit in a single
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
statements and 46,515 transactions; the batched path issues 360 and 67.
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

## Ingesting Windows events

DAD ingests Windows Event Log events. There are two collection paths and they
share everything after the point where a record becomes a staging line:

- **Pull (default): DAD polls the hosts itself over WinRM.** No collector to
  install on Windows, no second daemon, and the polling cadence is DAD's to
  control. Runs as a `Job` inside `dad-scheduler`.
- **Push: [OpenWEC](https://github.com/cea-sec/openwec) collects and a forwarder
  converts what it wrote.** Kept because an OpenWEC subscription already receives
  events pushed to it, which a pull model cannot recover for a host that is
  unreachable.

The design choice that makes both cheap is the same one, and it is deliberate:
**Windows events are converted into the record format the ingestor already
accepts, rather than the ingestor being extended to understand Windows events.**
`EventIngestor.stage_event` already parses an RFC 3339 timestamp as a single
token, so a converted line needs no importer changes at all, and the word
indexing, batching, crash checkpointing and event partitioning apply to Windows
events for free. A second ingest path would have had to reimplement all of that
and would drift.

```
                    ┌── poll_windows_events Job (in dad-scheduler) ──┐
Windows hosts ◄─WinRM─┘  wevtutil qe, per channel, on a per-host cycle │
                                                                       │
syslog/UDP:514 ─► LogStaging ─┐                                        │
                              │   OpenWEC ─► openwec.log ─► import_windows_events.rb
                              │                    (dad-windows, every 10s)
                              ▼                                        ▼
                    WindowsStaging ─► LogsToProcess ─► import_syslog.rb ─► Postgres
```

### Polling Windows hosts directly

#### Enabling it

Add the hosts under **WindowsTarget** in the UI (or via `/windows_targets`). Each
one needs an address, a WinRM username and password, a priority, and the channels
to read. Then make sure the poller Job exists and the scheduler is running:

```bash
bundle exec rails runner 'puts Job.where(script: "poll_windows_events").pluck(:name, :frequency)'
```

`db/seeds.rb` creates that Job, so a fresh install already has it. It runs every
60s; that number is only how often the due-list is swept, not how often any host
is polled.

No new service is needed under Docker Compose — the poller runs inside the
`scheduler` container, which already mounts the `Logs` volume that
`LogsToProcess` lives on.

#### What has to be true on the Windows side

- The WinRM listener must be reachable on **TCP 5986** (HTTPS). The poller
  connects out to the host; it does not open a listener for the host to call.
- The account needs read access to the event logs. A non-admin that can read
  `Security` is normally granted that through *Manage auditing and security log*;
  `Application` and `System` need no extra right.
- `wevtutil` must be present. It is part of every supported Windows edition, so
  this is only worth checking on a Server Core image with features stripped.

#### Priority bands and the adaptive interval

Polling every host as often as the busiest one needs does not scale, and polling
a quiet host every five minutes is pure load on both sides. So each host gets a
priority band, and within that band its interval adapts to how many events it is
actually producing:

| priority | fastest | slowest |
|---|---|---|
| Priority 1 | 60s | 5 min |
| Priority 2 | 5 min | 30 min |
| Priority 3 | 30 min | 6 h |

The interval aims at roughly 500 events per poll, clamped to the band:

```
interval = clamp(500 / smoothed_events_per_second, band_min, band_max)
```

Three details make that usable rather than twitchy:

- The rate is an exponential moving average, so one burst — a host rebooting, a
  logon storm — decays over a few polls instead of pinning the host at its fastest
  interval for hours.
- A change is only applied when it is at least 25% off the interval in force.
  Without that deadband the interval oscillates, and an oscillating interval is
  indistinguishable from a bug when you are trying to reason about when a host was
  last polled.
- A host that produced nothing takes its band's *slowest* interval, not zero.

Bands are rows in `polling_priorities`, editable in the UI. Adding a Priority 4 is
a form submission, not a code change.

#### Disabling a host

Each target has an **enabled** checkbox. Turning it off stops the polling but keeps
the row, and with it the measured event rate, the credentials and the poll history
— which is what you want when a host is down for maintenance. Deleting the row
throws all of that away and starts from scratch when the host returns.

#### Credentials

The WinRM password is a domain credential, so it is encrypted at rest by Rails'
`encrypts`; the `password` column holds ciphertext, not plaintext. Two
consequences for operations:

- Production must set `DAD_AR_ENCRYPTION_KEY` and `DAD_AR_ENCRYPTION_SALT` in
  `/etc/DAD/environment`. DAD **refuses to boot in production without them**
  rather than falling back to storing credentials in the clear. Generate both once:

  ```bash
  bundle exec rails runner 'puts SecureRandom.hex(32); puts SecureRandom.hex(32)'
  ```

- Changing either value makes stored Windows credentials unreadable. Generate them
  once and keep them; rotation means re-entering the WinRM passwords.

The credential is never rendered back to a browser — not on the HTML screens and
not in the `.json` forms. The edit form shows a blank password field, and
submitting it blank leaves the stored credential alone, so an unrelated edit
cannot silently wipe it.

#### Populating the list from Active Directory

Maintaining `WindowsTarget` rows by hand does not scale past a handful of
machines, and a hand-kept list drifts from the domain: the hosts that never get
added are the ones nobody knows are missing. DAD can query the directory for
computer objects and import the ones that are not already targets.

Configure a connection under **ActiveDirectoryConnection** (`/active_directory_connections`),
then run an import from **`/ad_import_batches/new`**: pick a directory, pick
workstations / servers / both, and DAD returns the machines it found that are not
already targets. Nothing is created until you confirm that list.

```bash
bundle exec rails runner 'puts ActiveDirectoryConnection.enabled.pluck(:name, :host, :port)'
```

**The import is preview-then-apply, and the preview is stored.** That is not a UX
nicety. A `WindowsTarget` row makes this server connect *out* to `address`
carrying a domain credential, so if the apply step took host names from the
submitted form, a crafted POST would add any host an attacker named and hand it
the WinRM credential — SSRF with a domain login attached, arriving through a form
whose only visible affordance is unchecking boxes. The candidate set is therefore
written server-side at preview time, and apply may only *remove* from it. A name
the directory never returned cannot be imported, whatever is posted. The audit
trail (who queried, what came back, what was applied) comes along for free.

Three behaviours in the query are load-bearing:

- **Paging.** Active Directory caps a search at `MaxPageSize` (1000 by default)
  and truncation is *silent* — the operator sees a plausible list with no hint
  that half the fleet is missing. `net-ldap` negotiates RFC 2696 paged results
  itself, so the fix is to not defeat it: no `:size` limit is ever passed.
- **Unknown operating system.** A machine joined to AD may be Linux, an
  appliance, or a Windows install whose `operatingSystem` attribute is simply
  unset. It matches neither the workstation nor the server filter. Those hosts
  are listed but **left unchecked**, and reported as a count, because a filter
  that quietly omits machines is how an operator ends up believing the fleet is
  fully covered.
- **Domain controllers are flagged.** A DC matches "servers", and bulk-enabling
  WinRM polling against one is a decision worth making deliberately rather than
  by accident.

Duplicate detection matches the FQDN *and* its first DNS label, case-insensitively.
AD returns `web01.corp.example.com`; an operator adding a host by hand types
`web01`. Treating those as different strings produces two targets for one machine,
which double-polls it and interleaves two independent offset states.

A connection holds **two** credentials, and they are not interchangeable:

| field | what it is for |
|---|---|
| `password` | binds to the directory to read computer objects |
| `poll_username` / `poll_password` | the WinRM login applied to every host this connection imports |

Both are encrypted at rest, the same as `WindowsTarget#password`. The second pair
exists because an imported host with no credential is a target that can never
poll — a feature that looks finished and is not. A connection missing it is
allowed (importing the inventory first is legitimate) but the import form says so
out loud. The polling credential is read from the connection at apply time and
never travels through the browser on the way back from the preview page.

A directory that is unreachable is an ordinary condition, not a 500: the failure
is recorded in `last_status` and shown, because "query failed" and "no new hosts"
look identical otherwise, and the second one is a lie.

#### Delta fetching, and why duplicates are accepted

`wevtutil` has no cursor, so the boundary is a time window: each poll reads
records whose `TimeCreated` falls since the last poll, **widened by 60s**. The
widening is not slack — a record's `TimeCreated` is when the event happened, not
when it reached the channel, and a service can log a timestamp and have the write
land seconds later. An exact boundary would drop those.

The cost is that records inside the overlap can be ingested twice. That is the
deliberate trade: a duplicate row is visible and merely inflates a count, whereas
a missed record is invisible and silently under-reports. There is no dedup
anywhere in the ingest path, so this is a choice, not an oversight.

Two more bounds, both to keep one host from dominating a cycle:

- At most **5000 records per channel per poll**, newest-first, so a runaway log
  yields its most recent records and the remainder arrives on the next poll.
- The **first** poll of a new host reads the last 24h, not the whole channel.
  Bootstrapping a full history would take minutes per channel and flood the queue
  on first contact.

#### Failure behaviour

A host that is down, firewalled, or has bad credentials is a normal condition in a
fleet of hundreds, not an exception. So:

- A failing host is recorded in `last_status` and rescheduled at its band's slowest
  interval. It is not retried every 60s, and it does not stop any other host from
  being polled.
- A failing *channel* does not lose the other channels on the same host: a host
  where `Security` is access-denied still yields its `Application` and `System`
  records, with the wevtutil error text kept in the status so the cause is legible.
- `wevtutil`'s exit code is checked. It exits 3 for an unknown channel and 5 for
  access denied; reporting those as "no events" would make a permission-locked
  channel look quiet.

#### Verifying the poller

```sql
select address, last_polled_at, next_poll_at, last_event_count, poll_count, last_status
from windows_targets order by last_polled_at desc nulls last;
```

`last_status` is where a problem will show up. `partial: Security: wevtutil exit 5:
Access is denied` means the channel list is wrong for that account, not that the
host is quiet.

### Collecting through OpenWEC instead

Point an OpenWEC subscription at its Files output driver:

```toml
[[subscription]]
name = "Security"

[subscription.output.files]
path = "/var/DAD/Logs/Windows"
file_name = "openwec.log"
format = "Json"
```

Then run the forwarder. Under systemd:

```bash
sudo install -m 0644 systemd/dad-windows.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dad-windows
journalctl -u dad-windows -f
```

Under Docker Compose it is behind a profile, because it needs an OpenWEC
installation this stack does not provide:

```bash
docker compose --profile windows up -d
```

| variable | default | meaning |
|---|---|---|
| `WINDOWS_INPUT` | `Logs/Windows/openwec.log` | the file OpenWEC writes |
| `WINDOWS_STAGING` | `Logs/WindowsStaging` | where converted lines are buffered |
| `WINDOWS_QUEUE` | `Logs/LogsToProcess` | the queue `dad-importer` polls |
| `WINDOWS_MAX_LINES` | `5000` | lines per queue file |
| `WINDOWS_POLL_INTERVAL` | `10` | seconds between input scans |

The poller uses the same `WINDOWS_STAGING` and `WINDOWS_QUEUE` defaults, so the
two paths publish to the queue identically.

#### Do not point OpenWEC at `Logs/LogStaging`

This is the one setup mistake that will silently corrupt data. `LogStaging`
belongs to the Rust syslog collector, whose startup recovery moves **every** file
it finds there into `LogsToProcess`, on the stated assumption that it is the only
writer in that directory. If OpenWEC writes there, the collector renames its
in-progress file away mid-append, and the tail of one file ends up in another.

Give OpenWEC its own directory (`Logs/Windows` above), and let the forwarder
buffer in a second one (`Logs/WindowsStaging`). The staging directory has to be
separate from the queue for the same class of reason: `LogQueue.pending` globs
`*` and excludes only `.processing` and `.offset` names, so a partially written
file sitting in the queue directory would be claimed and read while still being
appended to. The forwarder therefore writes to staging, `fsync`s, and only then
renames into the queue — the rename is what publishes the file.

#### Formats and field mapping

Four OpenWEC output formats are handled: `Json`, `Nxlog`, `Raw` (Windows XML) and
`JsonRaw`. A record is identified by its framing, not by guessing the format:
JSON records are one per line, a `Raw` XML record runs from `<Event` to
`</Event>`.

| DAD field | `Json` / `JsonRaw` | `Nxlog` | `Raw` XML |
|---|---|---|---|
| host (`System`) | `System.Computer` | `Host` / `Source` | `System/Computer` |
| timestamp (`generated`) | `System.TimeCreated` | `EventTime` | `System/TimeCreated` |
| service (`Service`) | `System.Provider.Name` | `SourceName` | `System/Provider Name` |
| body (`hunks`) | `EventData` as `key=value` | `Event` as `key=value` | `EventData` as `key=value` |

`EventID`, `Channel`, `Level`, `EventRecordID`, `Keywords`, `Task`, `Opcode` and
the provider name are emitted as explicit fields, and `EventData` values follow
as `data_<name>=<value>`. Field **keys** are downcased in every format so the
same event arriving as `Json` versus `Nxlog` does not index under two different
spellings; field **values** keep their case, because a username is data.

Timestamps are normalised to RFC 3339 with a literal `Z`. Windows emits 7-9
fractional digits and OpenWEC emits a UTC offset; both parse, but only the `Z`
form survives `stage_event`'s sanitiser intact — a `+` becomes a space, which
would split the timestamp across two tokens and mis-locate the service name.

#### The multi-line `Raw` trap

A rendered Windows event message (`RenderingInfo/Message`) can contain literal
newlines — a service-stopped event embeds the service's dependency list, a
process-creation event can embed a long command line. OpenWEC's Files driver
appends exactly one newline per record, which holds for `Json`, `Nxlog` and
`JsonRaw` but **not** for `Raw`.

So the forwarder cannot assume one line per record. It reads in byte chunks and
splits on record boundaries, tracking a byte offset that only advances past
records it has actually yielded. A record that has not finished arriving is left
in the buffer and resumed on the next pass; a record that never terminates is
dropped at a size ceiling rather than growing the buffer forever. One 4688 event
arrives as one row, not a dozen partial ones — and partial ones would be
indistinguishable from real data once they were in the database.

#### Verifying it works

```sql
select s.address, e.generated, e.hunks
from events e join systems s on s.id = e.system_id
where e.hunks like '%eventid=4688%' limit 5;
```

If the events are missing, check in order: `journalctl -u dad-windows` for
`no input at ...` (wrong `WINDOWS_INPUT`) or `skipped N unconvertible record(s)`
(format mismatch); then `ls Logs/WindowsStaging` (a file left there means the
forwarder is not flushing) and `ls Logs/LogsToProcess` (a file left there means
`dad-importer` is not running).

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
`DAD_OFFLINE_STORAGE_DIR` (default `offline_storage` under the app root, which
resolves to `/var/DAD/offline_storage` under systemd because the units set
`WorkingDirectory=/var/DAD` -- no unit sets the variable; owned by the service
user, mode from the umask). If the archive does not complete, the partition is **kept** and the next
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
  is in them, so restrict the directory yourself: nothing sets a mode on it, so
  it gets the umask default.

The `disk_utilization` job reports the partition holding the archives, not the
root filesystem, and names the directory it measured. If that partition cannot be
measured it says `disk utilization unknown` rather than `0%` — a missing reading
must not look like an empty disk.

Every entry point checks the schema shape before acting. On a database where the
partitioned shape was never built — one loaded from `db/schema.rb` rather than
from `db/migrate` — the job reports `event partitioning is Postgres-only;
nothing to do` instead of raising, so a stray `Job` row cannot crash the
scheduler.

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
| `poll_windows_events` | polls every Windows host whose `next_poll_at` has arrived (seeded every 60s) |

The `poll_windows_events` frequency is not the polling interval. It only sets how
often the due-list is swept; the interval that decides when any given host is
polled is computed per host — see
[priority bands](#priority-bands-and-the-adaptive-interval). So the Job runs often
and cheaply, and does nothing when nothing is due.

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
| `Viewer` | events, alerts, searches, systems, Windows targets and priority bands (read only) |
| `Commentator` | commenting on alerts, and Exclusions |
| `Taskmaster` | the Jobs screens |
| `Detective` | Displays and stored Searches |

`ACTION_RIGHTS` tightens specific actions past their controller's default. Adding
or editing a **WindowsTarget**, polling one on demand, and editing a
**PollingPriority** band all require `Admin`: a target row holds a domain
credential and names a host this server will connect out to, and widening a band
loosens how often DAD looks for new events. A Viewer can see both lists and the
guarantee each band offers, but cannot change either.

**ActiveDirectoryConnection** and **AdImportBatch** are `Admin`-only, for reading
as well as writing — deliberately stricter than `WindowsTarget`. Reading a target
list is a Viewer action, but a directory query returns the whole machine
inventory of a domain (hostname, OS, creation date), which is reconnaissance
value on its own, before anything is imported.

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

Most admin list screens (users, sessions, jobs, roles, rights, preferences,
comments, exclusions, searches, displays, hunks, statistics, Windows targets,
Active Directory connections) are paginated at 25 rows per page; `?page=N`
selects one. `systems` is deliberately unpaged -- it lists the hosts seen in the
last 24 hours -- and `services`, `words`, `alerts`, `events` and
`polling_priorities` are unpaged too.

---

## Development

```bash
bin/docker-test              # all three suites on Postgres, in Docker -- preferred
bundle exec rake test        # unit + controller tests, needs a Postgres cluster
bundle exec rake test:system # browser-level tests (Capybara rack-test)
bundle exec cucumber         # feature tests, needs a Postgres cluster
bundle exec brakeman -q      # static analysis, must report 0 warnings
bundle exec bundle-audit check # dependency CVEs
```

**Postgres is the only test engine.** SQLite was dropped, and the difference is
not theoretical: `Event.insertStatement` once emitted SQLite `?` placeholders
through `exec_query`, Postgres rejected them outright, and production could not
insert a single event while every SQLite job stayed green (RECOMMENDATIONS 3.2).
`events` and `events_words` are partitioned on Postgres and are not partitionable
on SQLite at all, so a SQLite suite never exercises the shape production queries;
the composite covering index on `events_words` is Postgres-only too.

`rake test` does **not** run `test/system` -- Railties excludes that directory
from the default task -- so the browser-level suite needs its own command.

`bin/docker-test` runs all three suites against the Compose `db` service and then
makes the same two assertions the CI `test` job makes — that `events` and
`events_words` really are partitioned, and that no index was left `INVALID` by a
failed `CONCURRENTLY` build. It passes extra arguments through to the container,
so `bin/docker-test bundle exec rails test test/models/event_test.rb` runs one
file, and `bin/docker-test bash` drops you into it.

CI runs six jobs (`.github/workflows/ci.yml`): the unit tests, the browser-level
system tests and the cucumber features on **Postgres**, an asset-precompile job,
a job that verifies the
systemd units, a `security` job (brakeman, bundle-audit, gitleaks), a **`docker`
job that builds this image and boots the stack**, and a **`collector` job** that
runs `cargo fmt --check`, `cargo clippy -D warnings`, and `cargo test` for the
Rust syslog collector.

The `docker` job is the one that would have caught the broken `Dockerfile.dev`.
Beyond building, it drives the running stack: it asserts the `migrate` service
left a partitioned `events`/`events_words` and at least one user, that the login
page actually renders (checking the body for "Could not find a JavaScript
runtime", so a missing runtime names itself instead of showing as a bare 500),
that an asset path the page emitted returns 200, and that a UDP packet sent to
`syslog`:514 ends up as a row in `events`. That last check is the only automated
test of the collector end-to-end through the importer — no Ruby-level job would
notice it failing to start. The `collector` job covers the unit and integration
tests, which the `docker` job does not run.

To run without Docker, point `DATABASE_URL` at a local cluster:

```bash
createuser dad && createdb -O dad dad_test
export DATABASE_URL=postgres://dad:dad@127.0.0.1:5432/dad_test
bundle exec rake db:migrate_from_scratch
bundle exec rake test
bundle exec rake test:system
bundle exec cucumber
```

Use `db:migrate_from_scratch`, not `db:migrate`, on an empty database: the
committed `db/schema.rb` is a portable dump that cannot express `PARTITION BY`,
and `db:migrate` loads that dump and skips `db/migrate` entirely, so the
partitioned shape is never built and the partitioning, backup and index tests
then fail for reasons that look like app bugs.

Tests that need a *second* database — the ingest tests that run the importer as a
subprocess — create throwaway databases of their own through
`test/support/scratch_database.rb`. That needs `CREATEDB` on the role behind
`DATABASE_URL`; `bin/docker-test` and CI both run as the cluster superuser.

Before deploying a change to the ingest path, read the comments in
`app/models/event.rb` around `storeEvent` / `flush_and_wait` and
`lib/log_queue.rb`. The checkpoint and the batch flush are coupled, and getting
the ordering wrong either loses rows or duplicates them.

---

## License

MIT — see [LICENSE](LICENSE).
