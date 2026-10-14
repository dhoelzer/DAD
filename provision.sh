#!/usr/bin/env bash

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
if ! [ -f "$ENV_FILE" ]; then
  sudo mkdir -p /etc/DAD
  DAD_DB_PASSWORD=$(openssl rand -hex 16)
  DAD_ADMIN_PASSWORD=$(openssl rand -hex 12)
  # Create the file with 0600 *before* writing: tee runs as root, so the
  # invoking user's umask does not apply and a plain redirect would land it
  # world-readable, exposing the DB password and session signing key.
  sudo install -m 600 /dev/null "$ENV_FILE"
  sudo tee "$ENV_FILE" > /dev/null << EOF0
export SECRET_KEY_BASE=$(openssl rand -hex 64)
export DAD_DB_USER=rails
export DAD_DB_PASSWORD=$DAD_DB_PASSWORD
export DAD_DB_NAME=events_prod
export DAD_DB_HOST=127.0.0.1
export DAD_ADMIN_USER=admin
export DAD_ADMIN_PASSWORD=$DAD_ADMIN_PASSWORD
EOF0
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

echo Configuring Postgresql
sudo -u postgres psql -c "CREATE USER $DAD_DB_USER WITH PASSWORD '$DAD_DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE $DAD_DB_NAME;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DAD_DB_NAME TO $DAD_DB_USER;"

if ! [ -L /var/DAD ]; then
  rm -rf /var/DAD
  ln -fs /vagrant /var/DAD
fi
if ! [ -L /home/vagrant/DAD ]; then
  ln -fs /vagrant /home/vagrant/DAD
fi

export RAILS_ENV=production 
cd /var/DAD
bundle install
sudo apt-get install -y libapache2-mod-passenger
sudo a2enmod passenger
sudo apache2ctl stop
sudo service apache2 stop
echo Adding Apache configurations for DAD.
sudo cat << EOF1 > /etc/apache2/sites-enabled/dad.conf
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
sudo cat << EOF4 > /etc/apache2/conf-available/dad-environment.conf
SetEnv SECRET_KEY_BASE $SECRET_KEY_BASE
SetEnv DAD_DB_USER $DAD_DB_USER
SetEnv DAD_DB_PASSWORD $DAD_DB_PASSWORD
SetEnv DAD_DB_NAME $DAD_DB_NAME
SetEnv DAD_DB_HOST $DAD_DB_HOST
EOF4
sudo a2enconf dad-environment

sudo cat << EOF2 > /etc/apache2/sites-enabled/dad-ssl.conf
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

		SSLCertificateFile	/etc/ssl/certs/ssl-cert-snakeoil.pem
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
ln -s /etc/apache2/mods-available/ssl.conf /etc/apache2/mods-enabled/ssl.conf
ln -s /etc/apache2/mods-available/ssl.load /etc/apache2/mods-enabled/ssl.load
# This is required for SSL to function:
ln -s /etc/apache2/mods-available/socache_shmcb.load /etc/apache2/mods-enabled/
sudo rm /etc/apache2/sites-enabled/000-default*
sudo apache2ctl start
export RAILS_ENV=production && cd /var/DAD && rake db:migrate
export RAILS_ENV=production && cd /var/DAD && rake db:seed
export RAILS_ENV=production && cd /var/DAD && perl syslog.pl &
echo Redirecting local logs and restarting rsyslog.
echo "*.*	@127.0.0.1" >> /etc/rsyslog.conf
/etc/init.d/rsyslog restart
export RAILS_ENV=production && cd /var/DAD && ruby import_syslog.rb > /tmp/import.log &
export RAILS_ENV=production && cd /var/DAD && ruby scheduler.rb > /tmp/schedule.log &
cat << EOF3
logger The system logger is now up and running and logs are being collected!
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
---------------------------------------------------
EOF3

