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

# Modules for DB and Event logs.  POSIX is required for Unix time stamps
use DBI;
use POSIX;

#Read in and evaluate the configuration values
open(FILE,"../dbconfig.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

$LastChecked = $ARGV[0];

# Grab all matching events that have occured since last alert job ran.
$SQL = "SELECT dad_sys_events.TimeGenerated, dad_sys_systems.System_Name, ".
	"Computer, Field_0 as 'Primary User', Field_1 as 'Primary Domain', ".
	"Field_2 as 'Primary Logon', Field_3 as 'Client User', ".
	"Field_4 as 'Client Domain', Field_5 as 'Client Logon' ".
	"FROM dad_sys_events, dad_sys_systems WHERE EventID='517' AND ".
	"dad_sys_events.SystemID=dad_sys_systems.System_ID AND ".
	"TimeWritten>'$LastChecked' AND Source='Security' ".
	"ORDER BY dad_sys_events.TimeGenerated";

$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to run alerting.\n");

$results_ref = &SQL_Query($SQL);
$num_results = @$results_ref;
if($num_results)
{
	while($row = shift(@$results_ref))
	{
		@this_row = @$row;
		$event_data = "Audit log on ".$this_row[1]." was reset from ".$this_row[2]." by ".
			$this_row[4]."::".$this_row[3]." (".$this_row[5].") for ".$this_row[7]."::".
			$this_row[6]." (".$this_row[8].")";
		$SQL = "INSERT INTO dad_alerts SET Alert_Time=".time().", Event_Time='".$this_row[0]."', ".
			"Event_Data='".$event_data."', Acknowledged=FALSE, Severity=5";
		$query = $dbh->prepare($SQL);
		$query->execute() or die("Error generating an alert!");
		$query->finish();
	}
}

	##################################################
	#
	# SQL_Query - Does the legwork for all SQL queries including basic error checking
	# 	Takes a SQL string as an argument
	#
	##################################################
	sub SQL_Query
	{
		my $SQL = $_[0];
		
		my $query = $dbh->prepare($SQL);
		$query -> execute();
		my $ref_to_array_of_row_refs = $query->fetchall_arrayref(); 
		$query->finish();
		return $ref_to_array_of_row_refs;
	}
