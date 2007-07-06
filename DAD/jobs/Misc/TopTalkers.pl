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

$SQL = "select Computer, count(SystemID) as 'Event Count' FROM dad.dad_sys_events group by Computer order by count(SystemID) DESC LIMIT 5";

$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to run alerting.\n");

$results_ref = &SQL_Query($SQL);
$num_results = @$results_ref;
if($num_results)
{
	open(OUTPUT, "> ../../web/TopTalkers.html");
	print OUTPUT "<table width=300px border=0>";
	print OUTPUT "<tr><th colspan=2>Most Active Servers</th></tr>";
	print OUTPUT "<tr><th>Server</th><th>Event Count</th></tr>\n";
	while($row = shift(@$results_ref))
	{
		@this_row = @$row;
		print OUTPUT "<tr><td><center><font size=-1>".$this_row[0]."</font></center></td><td><center><font size=-1>".$this_row[1]."</font></center></td></tr>\n";
	}
	print OUTPUT "</table>\n";
	close OUTPUT;
}
	
	$SQL="select EventID, count(EventID) as 'Event Count' FROM dad_sys_events group by EventID ORDER BY Count(EventID) DESC LIMIT 5";

	$results_ref = &SQL_Query($SQL);
$num_results = @$results_ref;
if($num_results)
{
	open(OUTPUT, ">> ../../web/TopTalkers.html");
	print OUTPUT "<table width=300px border=0>";
	print OUTPUT "<tr><th colspan=2>Most Common Events</th></tr>";
	print OUTPUT "<tr><th>Event ID</th><th>Event Count</th></tr>\n";
	while($row = shift(@$results_ref))
	{
		@this_row = @$row;
		print OUTPUT "<tr><td><center><font size=-1>".$this_row[0]."</font></center></td><td><center><font size=-1>".$this_row[1]."</font></center></td></tr>\n";
	}
	print OUTPUT "</table>\n";
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
