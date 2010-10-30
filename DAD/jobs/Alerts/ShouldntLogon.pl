#   Event Alerter
#    Copyright (C) 2006, David Hoelzer/Cyber-Defense.org
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

#!c:/perl/bin/perl.exe
require "../Reports/Reports.pm";
#Read in and evaluate the configuration values

$LastChecked = $ARGV[0];
$Severity = 1;
$AlertDescription = "Administrator Logon";
&Alert($AlertDescription, $Severity, $LastChecked, "528", 5, "Administrator", 7);
$AlertDescription = "Remote Desktop Administrator Logon";
&Alert($AlertDescription, $Severity, $LastChecked, "682", 5, "Administrator", 7);
