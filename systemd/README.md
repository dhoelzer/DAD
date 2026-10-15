# systemd units

These three units replace the `... &` backgrounding in `provision.sh`, which
meant the collector, importer and scheduler died on every VM reboot and nothing
restarted them (RECOMMENDATIONS.md 5.1).

| unit | runs | restarts |
|---|---|---|
| `dad-syslog` | `syslog.pl`, UDP/514 → `Logs/LogStaging` | always |
| `dad-importer` | `import_syslog.rb`, `LogsToProcess` → database | always |
| `dad-scheduler` | `scheduler.rb`, runs due `Job` rows | always |

`provision.sh` installs, enables and starts them. To do it by hand:

```bash
sudo install -m 0644 systemd/dad-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dad-syslog dad-importer dad-scheduler
systemctl status dad-importer
journalctl -u dad-importer -f
```

## Things worth knowing before you change them

**`EnvironmentFile` needs a different file.** systemd has no shell, so it cannot
source `/etc/DAD/environment` — that file uses `export KEY=value`, and systemd
would parse the literal string `export SECRET_KEY_BASE` as the variable name.
Every variable would come out empty and Rails would boot with a nil
`secret_key_base`. `provision.sh` therefore writes a second copy,
`/etc/DAD/environment.d/dad.conf`, in systemd's own `KEY=value` format. Keep the
two in sync if you add a variable.

**`/usr/bin/bundle` is the path in the Vagrant box** (Debian's `ruby` package
installs bundler there). On another host, override it in a drop-in rather than
editing the unit:

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
`syslog.pl` has no business holding database credentials. The one variable it
does read is `DAD_SYSLOG_DEBUG`, which echoes every received message to stdout
(the journal). Set it in a drop-in when you need to confirm the collector is
receiving anything at all.

**`Restart=always` plus `StartLimitIntervalSec=0`.** Without the latter, systemd
gives up after five fast restarts and the service stays down — which is the same
failure mode as `&`, just slower to notice. The backoff is `RestartSec=5`, so a
permanently broken configuration costs one restart every five seconds.
