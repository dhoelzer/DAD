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

#Grab the 5 top talkers

$HTML = "";

$SQL = "select System_Name, count(events.System_ID) as 'Event Count' 
	FROM dad.events, dad.dad_sys_systems 
	WHERE Time_Written>(UNIX_TIMESTAMP(NOW())-86400) 
		AND events.System_ID=dad_sys_systems.System_ID 
	group by events.System_ID order by count(events.System_ID) DESC LIMIT 5";

$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to run alerting.\n");

$results_ref = &SQL_Query($SQL);
$num_results = @$results_ref;
if($num_results)
{
	$HTML .="<table><tr><th colspan=2>Top Talkers</th></tr><tr><td><table width=300px border=0>";
	$HTML .="<tr><th colspan=2>Most Active Servers</th></tr>";
	$HTML .="<tr><th>Server</th><th>Event Count</th></tr>\n";
	while($row = shift(@$results_ref))
	{
		@this_row = @$row;
		$EventCount = $this_row[1];
		$EventCount =~ s/(?<=\d)(?=(\d\d\d)+$)/,/g;
		$HTML .="<tr><td><center><font size=-1>".$this_row[0]."</font></center></td><td><center><font size=-1>".$EventCount."</font></center></td></tr>\n";
	}
	$HTML .="</table></td>\n";
}
	
$SQL="
	select String,  count(event_fields.String_ID) as 'Event Count' 
		FROM event_fields, event_unique_strings 
		WHERE Position=5 
			AND event_unique_strings.String_ID=event_fields.String_ID
			AND (event_unique_strings.String > 0 AND event_unique_strings.String < 999999)
		group by event_fields.String_ID ORDER BY Count(event_fields.String_ID) DESC LIMIT 5";


	$results_ref = &SQL_Query($SQL);
$num_results = @$results_ref;
if($num_results)
{
	open(OUTPUT, "> ../../web/TopTalkers.html");
	print OUTPUT "$HTML";
	print OUTPUT "<td><table width=300px border=0>";
	print OUTPUT "<tr><th colspan=2>Most Common Events</th></tr>";
	print OUTPUT "<tr><th>Event ID</th><th>Event Count</th></tr>\n";
	while($row = shift(@$results_ref))
	{
		@this_row = @$row;
		$EventCount = $this_row[1];
		$EventCount =~ s/(?<=\d)(?=(\d\d\d)+$)/,/g;
		print OUTPUT "<tr><td><center><font size=-1>".$this_row[0]."</font></center></td><td><center><font size=-1>".$EventCount."</font></center></td></tr>\n";
	}
	print OUTPUT "</table></td></tr></table>\n";
	close OUTPUT;
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
