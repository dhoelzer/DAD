@echo off
set PATH=%PATH%;c:\perl\bin
echo Starting installation of Perl modules for DAD
cd DBI-1.50
call ppm install DBI.ppd
cd ..\DBD-mysql-3.0002
call ppm install DBD-mysql.ppd
cd ..\DBD-ODBC-1.13
call ppm install DBD-ODBC.ppd
cd ..\Convert-ASN1-0.20
call ppm install Convert-ASN1.ppd
cd ..\perl-ldap-0.33
call ppm install perl-ldap.ppd
cd ..\Win32-EventLog-0.073
call ppm install Win32-EventLog.ppd
cd "..\GD Stuff"
call ppm install GD.ppd
call ppm install GDtextutil.ppd
call ppm install GDGraph.ppd
cd ..
echo Done!