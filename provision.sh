#!/usr/bin/env bash
#
# Provisions a Debian Vagrant box into a running DAD instance.
#
# Safe to re-run. Every step is either idempotent by nature (apt-get install of
# an installed package) or guarded, and secrets are generated once and reused.
# The previous version re-ran CREATE USER / CREATE DATABASE (which error out),
# appended a duplicate line to /etc/rsyslog.conf on every run, re-seeded the
# database (duplicating every Role and Right), and backgrounded the three
# long-running processes with `&` so they died on reboot.
#
# set -e matters for idempotency: without it a failed step is ignored and the
# script reports success on a half-provisioned box.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y software-properties-common
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
# add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.0/debian jessie main'
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
apt-get install -y apt-transport-https ca-certificates
add-apt-repository 'deb https://oss-binaries.phusionpassenger.com/apt/passenger jessie main'
apt-get update
apt-get install -y ruby
apt-get install -y ruby-dev
apt-get install -y g++
apt-get install -y libsqlite3-dev
# terser (the JS compressor) runs through ExecJS, which shells out to a JS
# runtime. Without node, `rake assets:precompile` dies with
# "Could not find a JavaScript runtime" -- verified by hiding node from PATH.
# Uglifier needed one too; this was always a requirement, just never installed.
apt-get install -y nodejs
apt-get install -y apache2
# debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password password PASS'
# debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password_again password PASS'
apt-get install -y postgresql
apt-get install -y postgresql-server
apt-get install -y postgresql-client
apt-get install -y postgresql-server-dev-all

echo Generating secrets
# Secrets are generated at provision time and written to a root-owned file that
# is never committed. Re-running provision reuses them, so re-provisioning does
# not invalidate existing sessions or rotate the database password out from
# under the app.
ENV_FILE=/etc/DAD/environment
# systemd-format copy of the same values. systemd has no shell and cannot source
# the `export KEY=value` form above -- it would take the literal string
# "export SECRET_KEY_BASE" as a variable name and hand the service an empty
# value, booting Rails with a nil secret_key_base. See systemd/README.md.
SYSTEMD_ENV_DIR=/etc/DAD/environment.d
SYSTEMD_ENV_FILE=$SYSTEMD_ENV_DIR/dad.conf
if ! [ -f "$ENV_FILE" ]; then
  sudo mkdir -p /etc/DAD
  DAD_DB_PASSWORD=$(openssl rand -hex 16)
  DAD_ADMIN_PASSWORD=$(openssl rand -hex 12)
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  # Create the file with 0600 *before* writing: tee runs as root, so the
  # invoking user's umask does not apply and a plain redirect would land it
  # world-readable, exposing the DB password and session signing key.
  sudo install -m 600 /dev/null "$ENV_FILE"
  # tee, not `sudo tee ... << EOF` inside a `sudo cat << EOF >` redirect: the
  # redirect is performed by the calling shell, so `sudo cat > file` only
  # elevates the cat. It worked here only because the script already runs as
  # root, and silently writes nothing useful under `sudo -u`.
  sudo tee "$ENV_FILE" > /dev/null << EOF0
export SECRET_KEY_BASE=$SECRET_KEY_BASE
export DAD_DB_USER=rails
export DAD_DB_PASSWORD=$DAD_DB_PASSWORD
export DAD_DB_NAME=events_prod
export DAD_DB_HOST=127.0.0.1
export DAD_ADMIN_USER=admin
export DAD_ADMIN_PASSWORD=$DAD_ADMIN_PASSWORD
EOF0
fi

# Written every run, from the values just sourced, so the two files cannot drift
# apart on a re-provision. Same 0600 reasoning as above: this one holds the
# database password.
# shellcheck disable=SC1090
source "$ENV_FILE"
sudo mkdir -p "$SYSTEMD_ENV_DIR"
sudo install -m 600 /dev/null "$SYSTEMD_ENV_FILE"
sudo tee "$SYSTEMD_ENV_FILE" > /dev/null << EOF5
SECRET_KEY_BASE=$SECRET_KEY_BASE
DAD_DB_USER=$DAD_DB_USER
DAD_DB_PASSWORD=$DAD_DB_PASSWORD
DAD_DB_NAME=$DAD_DB_NAME
DAD_DB_HOST=$DAD_DB_HOST
EOF5

echo Configuring Postgresql
# Guarded: the unguarded CREATE USER / CREATE DATABASE made every re-run fail
# with "role already exists", and under set -e that would abort the script.
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DAD_DB_USER'" | grep -q 1 ||
  sudo -u postgres psql -c "CREATE USER $DAD_DB_USER WITH PASSWORD '$DAD_DB_PASSWORD';"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DAD_DB_NAME'" | grep -q 1 ||
  sudo -u postgres psql -c "CREATE DATABASE $DAD_DB_NAME;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DAD_DB_NAME TO $DAD_DB_USER;"

# -sfn, not -fs. -f alone dereferences: when the destination is already a
# symlink to a directory (which /var/DAD is after the first run), ln follows it
# and creates /vagrant/DAD instead of replacing the link. -n treats the symlink
# as the file to replace. The previous version guarded these with
# `if ! [ -L ... ]`, which left a stale link pointing at the wrong target in
# place.
ln -sfn /vagrant /var/DAD
ln -sfn /vagrant /home/vagrant/DAD

export RAILS_ENV=production
cd /var/DAD
bundle install
sudo apt-get install -y libapache2-mod-passenger
sudo a2enmod passenger
sudo service apache2 stop

echo Adding Apache configurations for DAD.
# install(1) writes the file with the mode set at creation, which avoids the
# create-then-chmod window a redirect leaves.
sudo install -m 0644 /dev/null /etc/apache2/sites-enabled/dad.conf
sudo tee /etc/apache2/sites-enabled/dad.conf > /dev/null << EOF1
<VirtualHost *:80>
    ServerName dad
    DocumentRoot /var/DAD/public
    <Directory /var/DAD/public>
        Allow from all
        Options -MultiViews
        Require all granted
    </Directory>
</VirtualHost>
EOF1
# Passenger reads app secrets from the Apache environment; without this the
# Rails app boots with a nil secret_key_base and refuses to run.
sudo install -m 0644 /dev/null /etc/apache2/conf-available/dad-environment.conf
sudo tee /etc/apache2/conf-available/dad-environment.conf > /dev/null << EOF4
SetEnv SECRET_KEY_BASE $SECRET_KEY_BASE
SetEnv DAD_DB_USER $DAD_DB_USER
SetEnv DAD_DB_PASSWORD $DAD_DB_PASSWORD
SetEnv DAD_DB_NAME $DAD_DB_NAME
SetEnv DAD_DB_HOST $DAD_DB_HOST
EOF4
sudo a2enconf dad-environment

sudo install -m 0644 /dev/null /etc/apache2/sites-enabled/dad-ssl.conf
sudo tee /etc/apache2/sites-enabled/dad-ssl.conf > /dev/null << EOF2
<IfModule mod_ssl.c>
        <VirtualHost *:443>
                ServerName dad
                DocumentRoot /var/DAD/public
    <Directory /var/DAD/public>
        Order allow,deny
        Allow from all
        Options -MultiViews
        SSLOptions +StdEnvVars
        Require all granted
    </Directory>

                ErrorLog ${APACHE_LOG_DIR}/error.log
                CustomLog ${APACHE_LOG_DIR}/access.log combined

                SSLEngine on

                SSLCertificateFile      /etc/ssl/certs/ssl-cert-snakeoil.pem
                SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

                SSLOptions +StrictRequire
                BrowserMatch "MSIE [2-6]" \
                                nokeepalive ssl-unclean-shutdown \
                                downgrade-1.0 force-response-1.0
                # MSIE 7 and newer should be able to use keepalive
                BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown

        </VirtualHost>
</IfModule>
EOF2
# a2enmod, not three hand-rolled symlinks into mods-enabled. The previous
# version used `ln -s`, which fails on the second run (file exists) and left
# socache_shmcb half-installed; a2enmod is already used correctly for passenger
# above and is idempotent.
sudo a2enmod ssl
sudo a2enmod socache_shmcb
# The default site would answer on :80 before dad.conf and serve DocumentRoot
# of /var/www. -f so a re-run does not fail on it already being gone.
sudo rm -f /etc/apache2/sites-enabled/000-default*
sudo apache2ctl start

echo Installing the DAD services.
# The previous version backgrounded these with `&`:
#   perl syslog.pl &
#   ruby import_syslog.rb > /tmp/import.log &
#   ruby scheduler.rb > /tmp/schedule.log &
# They died on VM reboot with no restart, no health check, and unbounded logs in
# /tmp. systemd owns them now: Restart=always, journald for logs, and enabled so
# they come back after a reboot. See systemd/README.md.
for unit in dad-syslog dad-importer dad-scheduler; do
  sudo install -m 0644 "/var/DAD/systemd/$unit.service" "/etc/systemd/system/$unit.service"
done
sudo systemctl daemon-reload
# The importer and scheduler write under log/ and share Logs/ with the Passenger
# process, which runs as www-data; the units run as www-data so the two agree on
# file ownership.
sudo chown -R www-data:www-data /var/DAD/Logs /var/DAD/log
sudo systemctl enable dad-syslog dad-importer dad-scheduler

export RAILS_ENV=production && cd /var/DAD && bundle exec rake db:migrate
export RAILS_ENV=production && cd /var/DAD && bundle exec rake db:seed
# db:seed is idempotent (find_or_create_by), so re-provisioning no longer
# duplicates every Role and Right.

# config.assets.compile = false means Rails will not compile an asset on demand,
# so the bundles have to exist before Passenger serves a page. Without this step
# a freshly provisioned host returns HTML that references /assets/... files that
# were never written, and the UI arrives unstyled.
export RAILS_ENV=production && cd /var/DAD && bundle exec rake assets:precompile

echo Redirecting local logs and restarting rsyslog.
# Guarded: the previous version appended unconditionally, so N re-runs produced
# N duplicate lines and the box's own logs were copied to the collector N times
# per event.
if ! grep -q '^\*\.\* * @127\.0\.0\.1' /etc/rsyslog.conf; then
  echo '*.*       @127.0.0.1' >> /etc/rsyslog.conf
fi
sudo systemctl restart rsyslog

# Started after the migrate/seed, so the importer does not race the schema.
sudo systemctl restart dad-syslog dad-importer dad-scheduler

cat << EOF3
---------------------------------------------------
Provisioning complete!

To connect to your DAD Vagrant point your browser
at 192.168.155.15.  You will receive a certificate
warning.  Accept the untrusted certificate.

You can log on with the initial administrative user:

Username: $DAD_ADMIN_USER
Password: $DAD_ADMIN_PASSWORD

Both are also in $ENV_FILE (root-owned, mode 600). Change the
password after first sign-in; that file is the only place it exists.

The provisioned server is automatically configured
to process logs, run the scheduler and to
begin receiving syslog messages.  Check the
interfaces of the vagrant to determine what the
public facing address is and you should be able to
begin consuming syslog messages immediately.

The three DAD services are managed by systemd:

  systemctl status dad-syslog dad-importer dad-scheduler
  journalctl -u dad-importer -f

They restart on failure and start on boot.
---------------------------------------------------
EOF3
