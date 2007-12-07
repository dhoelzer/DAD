@echo off
set PATH=%PATH%;c:\perl\bin
echo Starting installation of Perl modules for DAD
call ppm install DBI
call ppm install DBD-mysql
call ppm install DBD-ODBC
call ppm install Convert-ASN1
call ppm install perl-ldap
call ppm install Win32-EventLog
call ppm install GD
call ppm install GDtextutil
call ppm install GDGraph
call ppm install net-telnet
call ppm install yaml
call ppm install Win32api-Registry
call ppm install Win32-TieRegistry
call ppm install File-HomeDir-0.64
call ppm install AppConfig-1.63
call ppm install Text-Balanced-1.95
call ppm install Class-Base-0.03
call ppm install Class-Data-Inheritable-0.06
call ppm install Class-MakeMethods-1.009
call ppm install Parse-RecDescent
call ppm install Log-Log4perl
call ppm install Template-Toolkit
call ppm install SQL-Translator
