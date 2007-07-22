
@echo off
echo Backing up schema from %1
mysqldump -u root --password="All4Fun" --add-drop-table --create-options -h 127.0.0.1 --databases dad --no-data -q > Creates.sql