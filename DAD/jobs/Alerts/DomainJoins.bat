@echo off
rem This is just a wrapper to kick off the Perl job after setting the proper environment
c:
cd "\dad\jobs\Alerts"
call c:\perl\bin\perl.exe DomainJoins.pl %1