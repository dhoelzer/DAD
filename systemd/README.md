# systemd units

These units replace the `... &` backgrounding the original installer used, which
meant the collector, importer and scheduler died on every reboot and nothing
restarted them (RECOMMENDATIONS.md 5.1).

| unit | runs | restarts |
|---|---|---|
| `dad-syslog` | `syslog_collector` (Rust), UDP/514 → `Logs/LogStaging` | always |
| `dad-importer` | `import_syslog.rb`, `LogsToProcess` → database | always |
| `dad-scheduler` | `scheduler.rb`, runs due `Job` rows | always |
| `dad-windows` | `import_windows_events.rb`, OpenWEC output → `LogsToProcess` | always |

`dad-windows` is optional: it only does anything if OpenWEC is installed and
writing an input file. Enable it on its own, not as part of the base three.

Install, enable and start them yourself:

```bash
sudo install -m 0644 systemd/dad-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dad-syslog dad-importer dad-scheduler
systemctl status dad-importer
journalctl -u dad-importer -f

# optional, for Windows events
sudo mkdir -p -m 2775 /var/DAD/Logs/Windows
sudo chown dad:www-data /var/DAD/Logs/Windows
sudo systemctl enable --now dad-windows
journalctl -u dad-windows -f
```

The `Logs/Windows` directory is where OpenWEC's Files output driver writes; the
forwarder creates its own staging directory, but OpenWEC's is yours to create.
Do not point OpenWEC at `Logs/LogStaging` — that directory belongs to
`syslog_collector`, which moves every file it finds there into `LogsToProcess` at
startup. See README §Ingesting Windows events.

## Things worth knowing before you change them

**`EnvironmentFile` needs a different file.** systemd has no shell, so it cannot
source `/etc/DAD/environment` — that file uses `export KEY=value`, and systemd
would parse the literal string `export SECRET_KEY_BASE` as the variable name.
Every variable would come out empty and Rails would boot with a nil
`secret_key_base`. You therefore need a second copy,
`/etc/DAD/environment.d/dad.conf`, in systemd's own `KEY=value` format:

```bash
sudo install -d -m 755 /etc/DAD/environment.d
sudo install -m 600 /dev/null /etc/DAD/environment.d/dad.conf
# then write the same variables without `export`, e.g.
#   SECRET_KEY_BASE=...
#   DAD_DB_USER=...
```

Keep the two in sync if you add a variable.

**`/usr/bin/bundle` is Debian's path** (the `ruby` package installs bundler
there). On another distro, or under rbenv/rvm, override it in a drop-in rather
than editing the unit:

```bash
sudo systemctl edit dad-importer   # creates an override
# [Service]
# ExecStart=
# ExecStart=/usr/local/bin/bundle exec ruby import_syslog.rb
```

The empty `ExecStart=` is required — systemd appends to a list-valued setting
unless it is cleared first.

**All three run as `www-data`**, the user Passenger runs the web app as. That is
deliberate: the importer and the web app both write under `log/` and share
`Logs/`, and two different users would fight over ownership of those files. It
also means the hardening (`ProtectSystem=full`) is applied to a low-privilege
account rather than root.

**`dad-syslog` gets `CAP_NET_BIND_SERVICE` instead of root.** It binds port 514
and needs nothing else. It is also the only unit with no `EnvironmentFile`:
The collector has no business holding database credentials. The one variable it
does read is `DAD_SYSLOG_DEBUG`, which echoes every received message to stdout
(the journal). Set it in a drop-in when you need to confirm the collector is
receiving anything at all.

**`Restart=always` plus `StartLimitIntervalSec=0`.** Without the latter, systemd
gives up after five fast restarts and the service stays down — which is the same
failure mode as `&`, just slower to notice. The backoff is `RestartSec=5`, so a
permanently broken configuration costs one restart every five seconds.
