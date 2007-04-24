@echo off
echo Beginning installation
echo Please accept all default configuration options in all installers presented.
pause
set INSTALL_DIR=C:\DAD\Source
echo Installing from %INSTALL_DIR%...
echo -----------------------------------------------------------------
echo Installing Apache
echo Please accept all defaults.
call msiexec /i %INSTALL_DIR%\apache\apache_2.0.58-win32-x86-no_ssl.msi
echo -----------------------------------------------------------------
echo Modifying the Apache configuration file...
echo AddType application/x-httpd-php .php .html .htm >> "C:\Program Files\Apache Group\Apache2\conf\httpd.conf"
echo AddHandler application/x-httpd-php .php >> "C:\Program Files\Apache Group\Apache2\conf\httpd.conf"
echo AddHandler application/x-httpd-php .html >> "C:\Program Files\Apache Group\Apache2\conf\httpd.conf"
echo AddHandler application/x-httpd-php .htm >> "C:\Program Files\Apache Group\Apache2\conf\httpd.conf"
echo Overriding Document Root in httpd.conf
echo DocumentRoot "C:/DAD/web/html" >> "C:\Program Files\Apache Group\Apache2\conf\httpd.conf"
@rem copy /Y %INSTALL_DIR%\apache\httpd.conf "c:\program files\Apache group\apache2\conf"
echo -----------------------------------------------------------------
echo Before proceeding, you should have ALREADY downloaded and instal-
echo led MySQL and ActivePerl.  If you have not yet completed the
echo installation of these packages, please STOP NOW!  Go and install
echo these tools and then start this installation script.
echo " "
echo Please run the PHP installer that you downloaded at this point.
echo Please make sure to enable the "MySQL" and "MySQLi" modules.  You
echo must also configure the PHP installer to support an Apache 2.0.x
echo family server!!!
echo -----------------------------------------------------------------
echo Please hit enter AFTER you have installed the required packages.
pause
echo Stopping MySQL Service...
call sc stop mysql
ping -n 10 -w 1000 127.0.0.1 > nul
echo Moving MySQL Data files...
xcopy /e "C:\Program Files\MySQL\MySQL Server 5.0\data\*" "c:\DAD\data\"
echo Replacing MySQL configuration file...
copy /Y %INSTALL_DIR%\MySQL\my.ini "C:\Program Files\MySQL\MySQL Server 5.0\my.ini"
call sc start mysql
echo MySQL restarted.
echo -----------------------------------------------------------------
echo MySQL configuration completed
echo -----------------------------------------------------------------
echo Copying PHP ini file to the Windows directory.
copy "C:\program files\php\php.ini" C:\windows
rem Removed 4/23/07 - New PHP installer should take care of this.
rem echo Beginning PHP configuration
rem copy %INSTALL_DIR%\php\libmysql.dll "C:\program files\apache group\apache2\bin"
rem copy %INSTALL_DIR%\php\php*.dll c:\php
rem copy %INSTALL_DIR%\php\php.ini c:\php
rem erase c:\windows\php.ini
rem echo PHP configuration completed.
echo -----------------------------------------------------------------
echo Please left click the Apache icon in the icon tray and restart the 
echo Apache service.
pause
echo -----------------------------------------------------------------
echo Installing Perl modules...
cd %INSTALL_DIR%\perl
call installmodules.bat
echo -----------------------------------------------------------------
echo Installation Complete!  Adding in default data.  Please enter the
echo Database password that you configured for the root user when 
echo prompted.
echo -----------------------------------------------------------------
echo Building schema...
call "c:\Program Files\MySQL\MySQL Server 5.0\bin\mysql.exe" -u root -p < %INSTALL_DIR%\Creates.sql
echo Importing starter data...
call "c:\Program Files\MySQL\MySQL Server 5.0\bin\mysql.exe" -u root -p -D DAD < %INSTALL_DIR%\Starter_Data.sql
echo -----------------------------------------------------------------
echo Installing Java Runtime Environment...  Please accept all defaults.
call %INSTALL_DIR%\Java\jre-6u1-windows-i586-p-iftw.exe
echo Installing MySQL Java ODBC Connector...
copy %INSTALL_DIR%\Java\mysql-connector-java-5.0.5-bin.jar "C:\Program Files\Java\jre1.6.0_01\lib\ext"
echo Installation Completed!
echo -----------------------------------------------------------------
echo At this point you should log in using your web interface and add
echo servers to monitor!
echo In the future, until the scheduler is installed as a service, be
echo sure to run "C:\dad\jobs\start_scheduler.bat" if this window is
echo closed or the system restarted.
echo -----------------------------------------------------------------
echo Starting Scheduler.
@echo off
c:
cd \dad\jobs
call start_scheduler.bat

