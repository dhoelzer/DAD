@echo off
echo Beginning installation
echo Please accept all default configuration options in all installers presented.
pause
set INSTALL_DIR=C:\DAD\Source
echo Installing from %INSTALL_DIR%...
echo -----------------------------------------------------------------
echo While the MySQL installer runs, please take note of the following:
echo .
echo Please accept all of the defaults.
echo After initial installation, you will be given the option to configure the
echo server.  Please accept.
echo You can also accept all defaults in this section.  There are two exceptions to
echo consider:
echo   * It is not necessary to create a MySQL.com account.  You may 
echo     safely change this option.
echo   * When prompted regarding installation of MySQL as a Windows 
echo     Service, please make sure tha this option is configured.  
echo     On the same panel, please check the "Include bin directory 
echo     in Windows Path" option.
echo   * For simplest installation, set the default root password 
echo     to "All4Fun".  You can modify this later to make your 
echo     DAD more secure.
echo -----------------------------------------------------------------
call %INSTALL_DIR%\MySQL\mysql-5.0.21-win32\setup.exe
echo Please hit enter AFTER the MySQL installer completes.
pause
call sc stop mysql
pause
move "C:\Program Files\MySQL\MySQL Server 5.0\data" "c:\DAD\data"
copy /Y %INSTALL_DIR%\MySQL\my.ini "C:\Program Files\MySQL\MySQL Server 5.0\my.ini"
call sc start mysql
echo -----------------------------------------------------------------
echo MySQL installation completed
echo -----------------------------------------------------------------
pause
echo -----------------------------------------------------------------
echo Installing Apache
echo Please accept all defaults.
call msiexec /i %INSTALL_DIR%\apache\apache_2.0.58-win32-x86-no_ssl.msi
echo .
pause
copy /Y %INSTALL_DIR%\apache\httpd.conf "c:\program files\Apache group\apache2\conf"
echo -----------------------------------------------------------------
echo Beginning PHP installation
echo Please accept all defaults.  When prompted, select "Apache" as the server type.
call %INSTALL_DIR%\php\php-5.1.4-installer.exe
pause
copy %INSTALL_DIR%\php\libmysql.dll "C:\program files\apache group\apache2\bin"
copy %INSTALL_DIR%\php\php*.dll c:\php
copy %INSTALL_DIR%\php\php.ini c:\php
erase c:\windows\php.ini
echo PHP Installation completed.
echo -----------------------------------------------------------------
echo Please left click the Apache icon in the icon tray and restart the 
echo Apache service.
pause
echo -----------------------------------------------------------------
echo Installing PERL
call msiexec /i %INSTALL_DIR%\perl\ActivePerl-5.8.8.817-MSWin32-x86-257965.msi
cd %INSTALL_DIR%\perl
call installmodules.bat
echo -----------------------------------------------------------------
echo Installation Complete!  Adding in default data.  Please enter the
echo Database password when prompted.
echo Building schema...
call "c:\Program Files\MySQL\MySQL Server 5.0\bin\mysql.exe" -u root -p < %INSTALL_DIR%\Creates.sql
echo Importing starter data...
call "c:\Program Files\MySQL\MySQL Server 5.0\bin\mysql.exe" -u root -p -D DAD < %INSTALL_DIR%\Starter_Data.sql