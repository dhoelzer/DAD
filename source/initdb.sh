#!/bin/sh
echo Initializing schema...
mysql -u root -p < Creates.sql
echo Installing stored procedures
mysql -u root -p < Procedures.sql
echo Importing starter data...
mysql -u root -p -D DAD < Starter_Data.sql