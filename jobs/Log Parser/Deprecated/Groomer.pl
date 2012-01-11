#   DAD Windows Log Aggregator
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
open(FILE,"Aggregator.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

$Output = 1;
if($ARGV[0]) { $Output = 0; }
&_groomer;
exit(0);

sub _groomer
{
	my $days_of_history=31*24*60*60; #31 days of history
	my @Events_To_Prune;
	my %Explanations, %Retention_Times;
	
	$Groomer_Running = 1;
	if($Output)
	{
		print "Groomer running.\n";
	}
	&_get_events_to_prune();
	&_prune_events($event);
	&_prune_stats;
	$Groomer_Running = 0;


	sub _prune_stats
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
		my	$dsn, 						# Database connection
			$dbh;
		
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server to groom.\n");
	
		if($Output)
		{
			print "Pruning statistics\n";
		}
	
		my $mark = time()-$days_of_history;
		$SQL = "DELETE FROM dad_sys_events_groomed WHERE Timestamp<$mark";
		my $start_time = time();
		if($DEBUG!=1) { $deleted = (($dbh->do($SQL)) * 1); } else { $deleted=0; }
		if($Output)
		{
			print "Deleted $deleted rows.  Pruning took ".(time()-$start_time)." seconds.\n";
		}
		$SQL = "DELETE FROM dad_sys_event_stats WHERE Stat_Time<$mark";
		my $start_time = time();
		if($DEBUG!=1) { $deleted = (($dbh->do($SQL)) * 1); } else { $deleted=0; }
		if($Output)
		{
			print "Deleted $deleted rows.  Pruning took ".(time()-$start_time)." seconds.\n";
			print "Optimizing table to remove holes.\n";
		}
		my $start_time = time();
		$SQL = "OPTIMIZE TABLE dad_sys_event_stats";
		$dbh->do($SQL);
	}
	
	
	sub _prune_events
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
		my	$dsn, 						# Database connection
			$dbh;
		my	$starting_number, $ending_number;
		
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server to groom.\n");

		my $start_time = time();

	$results_ref = &SQL_Query("SELECT COUNT(*) FROM dad_sys_events");
	$row = shift(@$results_ref);
	$starting_number = @$row[0];
	
	$SQL = "CREATE TABLE dad_sys_events_pruning (".
  "`dad_sys_events_id` int(10) unsigned NOT NULL auto_increment,".
  "`SystemID` mediumint(8) unsigned NOT NULL default '0',".
  "`ServiceID` mediumint(8) unsigned NOT NULL default '0',".
  "`TimeWritten` int(10) unsigned NOT NULL default '0',".
  "`TimeGenerated` int(10) unsigned NOT NULL default '0',".
  "`Source` char(255) NOT NULL default '',".
  "`Category` char(255) NOT NULL default '',".
  "`SID` char(64) character set latin1 NOT NULL default '',".
  "`Computer` char(255) NOT NULL default '',".
  "`EventID` mediumint(8) unsigned NOT NULL default '0',".
  "`EventType` tinyint(3) unsigned NOT NULL default '0',".
  "`Field_0` varchar(760) default NULL,".
  "`Field_1` varchar(760) default NULL,".
  "`Field_2` varchar(760) default NULL,".
  "`Field_3` varchar(760) default NULL,".
  "`Field_4` varchar(760) default NULL,".
  "`Field_5` varchar(760) default NULL,".
  "`Field_6` varchar(760) default NULL,".
  "`Field_7` varchar(760) default NULL,".
  "`Field_8` varchar(760) default NULL,".
  "`Field_9` varchar(760) default NULL,".
  "`Field_10` varchar(760) default NULL,".
  "`Field_11` varchar(760) default NULL,".
  "`Field_12` varchar(760) default NULL,".
  "`Field_13` varchar(760) default NULL,".
  "`Field_14` varchar(760) default NULL,".
  "`Field_15` varchar(760) default NULL,".
  "`Field_16` varchar(760) default NULL,".
  "`Field_17` varchar(760) default NULL,".
  "`Field_18` varchar(760) default NULL,".
  "`Field_19` varchar(760) default NULL,".
  "`Field_20` varchar(760) default NULL,".
  "`Field_21` varchar(760) default NULL,".
  "`Field_22` varchar(760) default NULL,".
  "`Field_23` varchar(760) default NULL,".
  "`Field_24` varchar(760) default NULL,".
  "`Field_25` varchar(760) default NULL,".
  "`idxID_Code` char(64) default NULL,".
  "`idxID_Kerb` char(64) default NULL,".
  "`idxID_NTLM` char(64) default NULL,".
  "PRIMARY KEY  (`dad_sys_events_id`),".
  "KEY `idxEventID` (`EventID`),".
  "KEY `idxSID` (`SID`),".
  "KEY `idxTimestamp` (`TimeGenerated`),".
  "KEY `idxIDbyCode` (`idxID_Code`(10)),".
  "KEY `idxIDbyKerb` (`idxID_Kerb`(15)),".
  "KEY `idxIDbyNTLM` (`idxID_NTLM`(10)),".
  "KEY `idxNTLMCode` (`Field_3`(15))".
") ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Normalized Windows Events' ";

		$dbh->do($SQL) or die("Could not create pruner table.");
	$SQL = "CREATE TABLE dad_sys_events_tmp (".
  "`dad_sys_events_id` int(10) unsigned NOT NULL auto_increment,".
  "`SystemID` mediumint(8) unsigned NOT NULL default '0',".
  "`ServiceID` mediumint(8) unsigned NOT NULL default '0',".
  "`TimeWritten` int(10) unsigned NOT NULL default '0',".
  "`TimeGenerated` int(10) unsigned NOT NULL default '0',".
  "`Source` char(255) NOT NULL default '',".
  "`Category` char(255) NOT NULL default '',".
  "`SID` char(64) character set latin1 NOT NULL default '',".
  "`Computer` char(255) NOT NULL default '',".
  "`EventID` mediumint(8) unsigned NOT NULL default '0',".
  "`EventType` tinyint(3) unsigned NOT NULL default '0',".
  "`Field_0` varchar(760) default NULL,".
  "`Field_1` varchar(760) default NULL,".
  "`Field_2` varchar(760) default NULL,".
  "`Field_3` varchar(760) default NULL,".
  "`Field_4` varchar(760) default NULL,".
  "`Field_5` varchar(760) default NULL,".
  "`Field_6` varchar(760) default NULL,".
  "`Field_7` varchar(760) default NULL,".
  "`Field_8` varchar(760) default NULL,".
  "`Field_9` varchar(760) default NULL,".
  "`Field_10` varchar(760) default NULL,".
  "`Field_11` varchar(760) default NULL,".
  "`Field_12` varchar(760) default NULL,".
  "`Field_13` varchar(760) default NULL,".
  "`Field_14` varchar(760) default NULL,".
  "`Field_15` varchar(760) default NULL,".
  "`Field_16` varchar(760) default NULL,".
  "`Field_17` varchar(760) default NULL,".
  "`Field_18` varchar(760) default NULL,".
  "`Field_19` varchar(760) default NULL,".
  "`Field_20` varchar(760) default NULL,".
  "`Field_21` varchar(760) default NULL,".
  "`Field_22` varchar(760) default NULL,".
  "`Field_23` varchar(760) default NULL,".
  "`Field_24` varchar(760) default NULL,".
  "`Field_25` varchar(760) default NULL,".
  "`idxID_Code` char(64) default NULL,".
  "`idxID_Kerb` char(64) default NULL,".
  "`idxID_NTLM` char(64) default NULL,".
  "PRIMARY KEY  (`dad_sys_events_id`),".
  "KEY `idxEventID` (`EventID`),".
  "KEY `idxSID` (`SID`),".
  "KEY `idxTimestamp` (`TimeGenerated`),".
  "KEY `idxIDbyCode` (`idxID_Code`(10)),".
  "KEY `idxIDbyKerb` (`idxID_Kerb`(15)),".
  "KEY `idxIDbyNTLM` (`idxID_NTLM`(10)),".
  "KEY `idxNTLMCode` (`Field_3`(15))".
") ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Normalized Windows Events' ";
		$dbh->do($SQL) or die("Could not create pruner table.");
			
		$SQL = "RENAME TABLE dad_sys_events TO dad_tmp, dad_sys_events_pruning TO dad_sys_events, dad_tmp TO dad_sys_events_pruning";
		$dbh->do($SQL) or die("Could not rename tables for groomer.");

		foreach $event (@Events_To_Prune)
		{
			if($event == 0) { next; } # Don't try to process default rule
			if($Output)
			{
				print "Pruning event ID $event\n";
			}
		$SQL = "INSERT INTO dad_sys_events_tmp (SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM) SELECT SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM FROM dad_sys_events_pruning WHERE EventID='$event' AND TimeGenerated>".(time() - $Retention_Times{$event});
#			if($Output) { print "\t$SQL\n".time()." - ".$Retention_Times{$event}."\n"; }
			my $query = $dbh->prepare($SQL);
			$query->execute() or die("Error pruning!  Could not complete prune for $event.");
			$query->finish();
		}
		if($Output)
		{
			print "Pruning default rule\n";
		}
		$SQL = "INSERT INTO dad_sys_events_tmp (SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM) SELECT SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM FROM dad_sys_events_pruning WHERE TimeGenerated>".(time()-$Retention_Times{0});
		foreach $event (@Events_To_Prune)
		{
			if($event == 0)
			{
				next;
			}
			$SQL .= " AND NOT EventID='$event'";
		}
		if($Output){print "Default rule: $SQL\n";}
		my $query = $dbh->prepare($SQL);
		$query->execute() or die("Error pruning!  Could not complete default rule.");
		$query->finish();
		if($Output)
		{
			print "Pruning Complete.  Pruning took ".(time()-$start_time)." seconds.\n";
		}
	$SQL = "DROP TABLE dad_sys_events_pruning";
	$dbh->do($SQL);

	$results_ref = &SQL_Query("SELECT COUNT(*) FROM dad_sys_events_tmp");
	$row = shift(@$results_ref);
	$ending_number = @$row[0];
	if($Output)
	{
		print "There were $starting_number events, there are now $ending_number events.  Groomed ".($starting_number - $ending_number).".\n";
	}
	if($Output)
	{
		print "Reshuffling table and inserting new events.\n";
	}
	$SQL = "RENAME TABLE dad_sys_events TO dad_tmp, dad_sys_events_tmp TO dad_sys_events, dad_tmp TO dad_sys_events_pruning";
	$dbh->do($SQL) or die("Could not rename tables for groomer.");
	$SQL = "INSERT INTO dad_sys_events (SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM) SELECT SystemID, ServiceID, TimeWritten, TimeGenerated, Source, ".
				"Category, SID, Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, ".
				"Field_6, Field_7, Field_8, Field_9, Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, ".
				"Field_17, Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, idxID_Code, ".
				"idxID_Kerb, idxID_NTLM FROM dad_sys_events_pruning";
	my $query = $dbh->prepare($SQL);
	$query->execute() or die("Could not copy back new records!");
	$query->finish();
	if($Output){ print "Dropping tmp table.\n"; }
	$SQL = "DROP TABLE dad_sys_events_pruning";
	$dbh->do($SQL);



}
	
	##########################
	# Grabs the numbers of the events to process
	sub _get_events_to_prune
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
		my	$dsn, 						# Database connection
			$dbh;
		
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server to import the list of servers to poll.\n");
	
		$results_ref = &SQL_Query("SELECT Event_ID,Explanation,Retention_Time FROM dad_sys_events_aging");
		# Populate the arrays and mappings
		while($row = shift(@$results_ref) ) 
		{
			@this_row = @$row;
			my $event_id = $this_row[0];
			my $explanation = $this_row[1];
			my $retention_time = $this_row[2];
			
			unshift(@Events_To_Prune, $event_id);
			$Explanations{$event_id} = $explanation;
			$Retention_Times{$event_id} = $retention_time;
		}
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
