@echo off
echo Backing up schema from %1
mysqldump -u root -p --add-drop-table --create-options -h %1 --databases dad --no-data -q > Creates.sql