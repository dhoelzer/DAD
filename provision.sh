#!/usr/bin/env bash

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y software-properties-common
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db 
add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.0/debian jessie main'
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
apt-get install -y apt-transport-https ca-certificates
add-apt-repository 'deb https://oss-binaries.phusionpassenger.com/apt/passenger jessie main'
apt-get update
apt-get install -y apache2
debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password password PASS'
debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password_again password PASS'
apt-get install -y mariadb-server
apt-get install -y mariadb-client
echo Configuring MariaDB
mysql -uroot -pPASS -e "SET PASSWORD = PASSWORD('');"
mysql -uroot  -e "CREATE USER 'rails'@'%' IDENTIFIED BY 'example';"
mysql -uroot -e "UPDATE user SET password=PASSWORD('example') WHERE user='rails';" mysql
mysql -u root -e "CREATE DATABASE events_prod;"
mysql -u root -e "GRANT ALL PRIVILEGES ON events_prod.* TO 'rails'@'%';"
apt-get install -y libmariadbclient-dev

if ! [ -L /var/DAD ]; then
  rm -rf /var/DAD
  ln -fs /vagrant /var/DAD
fi
if ! [ -L /home/vagrant/DAD ]; then
  ln -fs /vagrant /home/vagrant/DAD
fi

export RAILS_ENV=production && cd /var/DAD && bundle install
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
export RAILS_ENV=production && cd /var/DAD && ruby import_syslog.rb > /tmp/import.log &
export RAILS_ENV=production && cd /var/DAD && ruby scheduler.rb > /tmp/schedule.log &
cat << EOF3
---------------------------------------------------
Provisioning complete!

To connect to your DAD Vagrant point your browser
at 192.168.155.15.  You will receive a certificate
warning.  Accept the untrusted certificate.

You can log on with the initial administrative user:

Username: admin
Password: Password1

The provisioned server is automatically configured
to process logs, run the scheduler and to
begin receiving syslog messages.  Check the
interfaces of the vagrant to determine what the
public facing address is and you should be able to
begin consuming syslog messages immediately.
---------------------------------------------------
EOF3

