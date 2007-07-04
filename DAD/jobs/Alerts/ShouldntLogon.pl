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
$SQL = "SELECT TimeGenerated, Field_0 as 'User',Field_1 as 'Domain', ".
	"Computer as 'Logged onto', Field_3 as 'Logon type', ".
	"Field_6 as 'From Computer' ".
	"FROM dad_sys_events WHERE EventID='528' AND Field_0='Administrator' AND TimeWritten>'$LastChecked' AND Source='Security' ORDER BY TimeGenerated";

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
		$logon_type = $this_row[4];
		$event_data = $this_row[1]."/".$this_row[2].": ".
			($logon_type=='2' ? "Interactive" :
				($logon_type=='3' ? "Network" :
					($logon_type=='4' ? "Scheduled Task" :
						($logon_type=='5' ? "Service Start" :
							($logon_type=='7' ? "Screen Unlock" :
								($logon_type=='8' ? "Cleartext/IIS" :
									($logon_type=='9' ? "New Credentials":
										($logon_type=='10' ? "Remote Desktop" :
											($logon_type=='11' ? "Cached Credentials" :
												"Unknown")
			)))))))) ." Logon to: ".$this_row[3]." from ".$this_row[5];
		$SQL = "INSERT INTO dad_alerts SET Alert_Time=".time().", Event_Time='".$this_row[0]."', ".
			"Event_Data='".$event_data."', Acknowledged=FALSE, Severity=1";
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
