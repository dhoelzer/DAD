#!/usr/bin/env bash
sudo apt-get install software-properties-common 
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db 
sudo add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/10.0/ubuntu trusty main'
sudo apt-get update
sudo apt-get install -y apache2
sudo apt-get install -y mariadb-server
sudo apt-get install -y mariadb-client
bundle install

