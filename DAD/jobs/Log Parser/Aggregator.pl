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

# Threaded model for multiple queues
use threads;
use threads::shared;
use Thread::Queue;
#use Thread eval;
# Modules for DB and Event logs.  POSIX is required for Unix time stamps
use DBI;
use POSIX;
use Win32::EventLog;
use GD::Graph::lines;

################################################################
#
# The following are "Shared".  This means that all threads can see the contents or modify the contents of these
my $Groomer_Running : shared;	#Status of the log groomer
my $Time_To_Die : shared;		# Windows threads has a nasty memory leak.  This is used to force
								# all threads to exit and then to die gracefully.
my $Pending_Running : shared;
my $DEBUG : shared;
my $MYSQL_SERVER : shared;
my $MYSQL_USER : shared;
my $MYSQL_PASSWORD : shared;
my %LogThese : shared;			#Which logs on each server to log from
my %Processing : shared;		#Hash used to track logs currently being processed
my %Filtered_Events : shared;	#Tracks events to ignore
my @Field_Lengths : shared;		#Max field sizes for database fields
my %Status : shared;
my %Priority : shared;
my $SQL_Queue : shared;			#Queue used to transfer inserts to insert threads
my $Process_Queue : shared;		#Queue used to mark next logs to process
my $High_Priority_Queue : shared; #Queue used for priority 1 systems
my $MAX_EXECUTION_TIME : shared;#Maximum time a thread can spend processing any given log.
##################################################################

my $Groomer_Hour;
my $BackupSQLFile;
my $TZ_Offset;
my $Stat_Time_Period;
my $OUTPUT_LOCATION;
my $Total_Run_Time;
my $EVENT_HANDLER_THREADS;
my $INSERT_THREADS;
my %Insert_Threads;				#Hash containing handles to the insert threads
my %Log_Threads;				#Hash containing handles to the event log threads
my @Systems;					#Systems to process
my $System_Started;				# Time this process started

#Read in and evaluate the configuration values
open(FILE,"Aggregator.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

#Initialize shared variables
$Time_To_Die = 0;
$Groomer_Running = 0;
$Pending_Running = 0;

# Create the queues.  These queues are used to transfer servers to the event queues and events to the SQL queues.
$SQL_Queue = Thread::Queue->new;
$Process_Queue = Thread::Queue->new;
$High_Priority_Queue = Thread::Queue->new;
$System_Started = mktime(localtime());

# Initialize the list of filtered events before starting threads
# These are events that we never insert into the database
&_get_filtered_events();
&_insert_pending_events();
	
#Fire up the threads
&_start_threads;
print "Entering event loop\n";
#Start the main event loop
my $loop=0;
while(1)						#Always running, never getting anywhere
{
	my $Time_Remaining;
	my $system;
	my $pending, $hpending;
	my $Run_Groomer = 0;
	
	if(! $Groomer_Running) 		#Don't start a groomer if there is a groomer already
	{
		$Run_Groomer = &_check_for_groomer;
		if($Run_Groomer)
		{
			my $thread;
			$thread = threads->new(\&_groomer);	#Spin and detach a groomer thread
			$thread->detach();
		}
	}
	$loop++;					# Number of times through this run
#	$Time_Remaining = $Total_Run_Time - (mktime(localtime())- $System_Started);
	$Time_Remaining = "Continuously running.";
	if((($loop % 120) == 0))		# Update the stat graphs every 10 minutes
	{
		open(STATS, ">>$OUTPUT_LOCATION/stats.html") or print "Couldn't open stats file.\n";
		print STATS "Building statistics\n";
		close(STATS);
		&_build_stats();		# This locks the main thread during stat creation
	}
	{
		#Recreate the quick stats every time through.
		open(STATS, ">$OUTPUT_LOCATION/stats.html") or print "Couldn't open stats file.\n";
		print STATS<<End;
		<html>
		<head>
		<title>Aggregator Status</title>
		<meta http-equiv="Refresh" CONTENT="5;URL=/stats/stats.html" />
		</title>
		<body>
End
		print STATS "<hr />\n";
		foreach $status ((sort keys(%Status)))
		{
			print STATS "$status : $Status{$status}<br />\n";
		}
		print STATS "<hr />\n";
		print STATS $SQL_Queue->pending()." inserts pending.<br/>\n";
		$pending = $Process_Queue->pending();
		$hpending = $High_Priority_Queue->pending();
		if($pending > 15) 				#More than 15 queues pending, decrease processing time
		{ 
			$MAX_EXECUTION_TIME = int((($MAX_EXECUTION_TIME / 2)<20 ? 20 : $MAX_EXECUTION_TIME/2));
		}
		if($pending < 3)				#Fewer than 3 queues pending, increase the processing time
		{
			$MAX_EXECUTION_TIME = ($MAX_EXECUTION_TIME > 150 ? 150 : int($MAX_EXECUTION_TIME * 1.5));
			$MAX_EXECUTION_TIME = ($MAX_EXECUTION_TIME > 150 ? 150 : $MAX_EXECUTION_TIME);
		}
		print STATS "$pending systems awaiting processing.<br >\n";
		print STATS "$hpending priority 1 systems waiting.<br >\n";
		print STATS "Base execution time per log: $MAX_EXECUTION_TIME<br >\n";
		print STATS "Run time remaining: $Time_Remaining<br >\n";
		print STATS "<hr />";
		if($Groomer_Running)
		{
			print STATS "Groomer is currently running.  Please be patient.\n";
		}
		if($Pending_Running)
		{
			print STATS "Inserting outstanding queries.\n";
		}
		close(STATS);
	}
# Disabled for testing	if($Time_Remaining < 1)				#If we've run out of time and there's no groomer, signal the end
#	{
#		if((!$Groomer_Running) && (!$Pending_Running)) { $Time_To_Die = 1; }
#		if(($SQL_Queue->pending()==0)) #Enough time for the SQL threads to complete if sleeping
#		{
#			my $safe_to_die = 1;
#			foreach $status ((sort keys(%Status)))
#			{
#				if ($Status{$status} ne "Dead.") { $safe_to_die = 0; }
#			}
#			if($safe_to_die)
#			{
#				print "All log threads dead, SQL queue empty.  Force exiting.\n";
#				exit;
#			}
#			else { print "There are still locked threads pending.  Delaying exit.\n"; }
#		}
#	}
							#See which queues are waiting and queue them as appropriate
	@Systems = &_get_systems_to_process;
	foreach $system (@Systems)
	{
		if(!$Processing{$system}) #pseudo-atomic to avoid race condition
		{
			$Processing{$system} = 1;
			if($Priority{$system} < 1)	#Any priority less than 1 means DISABLED
			{
				next;
			}
			if($Priority{$system} == 1)
			{
				$High_Priority_Queue->enqueue($system);
			}
			else
			{
				$Process_Queue->enqueue($system);
			}
		}
	}

	sleep(5);				# 5 Seconds between interations
}
# If we reach here, time to die has passed and all other threads have exited
print "No more threads!\n";

############################################################################
#
# Subroutines follow
#
############################################################################

sub _event_thread
{
	##################################################
	#
	# record_event - Push the event into the database
	# Takes as arguments the timestamp, reporting system, service followed by an array of fields
	# Maintains the %System_IDs and %Service_IDs hashes
	#
	##################################################
	sub record_event
	{
		my $time, $system, $service, @values, @row, $row, $result_ref, $rows_returned, $idxID_Code, $idxID_Kerb, $idxID_NTLM;
		($system, $service, $timewritten, $timegenerated, $source, $category, $sid, $computer, $eventid, $eventtype, @values) = @_;
		
		# See if the service is known.  If not, get it from the database or create a new ID:
		if(! $Service_IDs{"$service"})
		{
			$result_ref = &_SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
			$rows_returned = scalar @$result_ref;
			if($rows_returned < 1)
			{
				&_SQL_Insert("INSERT INTO dad_sys_services (Service_Name) VALUES ('$service')");
				$result_ref = &_SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
				$rows_returned = scalar @$result_ref;
				if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (service)!\n"); }
			}
			$row = shift(@$result_ref);
			$Service_IDs{"$service"} = @$row[0];
		}
	
		# See if the system is known.  If not, get it from the database or create a new ID:
		if(! $System_IDs{"$system"})
		{
			$result_ref = &_SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
			$rows_returned = scalar @$result_ref;
			if($rows_returned < 1)
			{
				&_SQL_Insert("INSERT INTO dad_sys_systems (System_Name) VALUES ('$system')");
				$result_ref = &_SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
				$rows_returned = scalar @$result_ref;
				if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (system)!\n"); }
			}
			$row = shift(@$result_ref);
			$System_IDs{"$system"} = @$row[0];
		}

		
		# Now insert a new event with the correct system and service IDs
		$idxID_Code = substr("$eventid $values[2]",0,64);
		$idxID_Kerb = substr("$eventid $values[4]",0,64);
		$idxID_NTLM = substr("$eventid $values[3]",0,64);
		$SQL_Queue->enqueue("('". $System_IDs{"$system"} ."', ". $Service_IDs{"$service"} .", ".
			"'$timewritten', '$timegenerated', '$source', '$category', '$sid', '$computer', '$eventid', '$eventtype', ".
			"'$values[0]', '$values[1]', '$values[2]', '$values[3]', '$values[4]', ".
			"'$values[5]', '$values[6]', '$values[7]', '$values[8]', '$values[9]', ".
			"'$values[10]', '$values[11]', '$values[12]', '$values[13]', '$values[14]', '$values[15]', '$values[16]', ".
			"'$values[17]', '$values[18]', '$values[19]', '$values[20]', '$values[21]', '$values[22]', '$values[23]',".
			"'$values[24]', '$values[25]', '$idxID_Code', '$idxID_Kerb', '$idxID_NTLM')");
#			/* idxID_Code = EventID + Field_2
#			   idxID_Kerb = EventID + Field_4
#			   idxID_NTLM = EventID + Field_3
#			*/

	}

	sub addslashes
	{
		my $String = shift;
		$String =~ s/(["'\%\\])/\\\1/g;
		$String =~ s/[^[:print:]]//g;
		return $String;
	}
	##################################################
	#
	# SQL_Query - Does the legwork for all SQL queries including basic error checking
	# 	Takes a SQL string as an argument
	#
	##################################################
	sub _SQL_Query
	{
		my $SQL = $_[0];
		
		my $query = $dbh->prepare($SQL);
		$query -> execute();
		my $ref_to_array_of_row_refs = $query->fetchall_arrayref(); 
		$query->finish();
		return $ref_to_array_of_row_refs;
	}
	
	##################################################
	#
	# SQL_Insert - Does the legwork for all SQL inserts including basic error checking
	# 	Takes a SQL string as an argument
	#
	##################################################
	sub _SQL_Insert
	{
		my $SQL = $_[0];
		my $query = $dbh->prepare($SQL);
		if($DEBUG){return; print"$SQL\n";return;}
		$query -> execute();
		$query->finish();
	}

	#########################
	# Populates the filtered events hash
	sub _get_filtered_events
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
		my	$dsn, 						# Database connection
			$dbh;
	# Open the database connection.  We turn auto commit off so that we can do block inserts.
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server to update filtered event list.\n");
	
		%Filtered_Events;
	# Fetch the list of services to filter
		$results_ref = &_SQL_Query("SELECT Event_ID, Description FROM dad_sys_filtered_events");
		while($row = shift(@$results_ref))
		{
			@this_row = @$row;
			$Filtered_Events{$this_row[0]}=1;
		}
	}									#Implicit unlock of %Filtered_Events

	#/********************************************************
	# * mark_log_processed($Logfile, $System, $LastEntryProcessed, $total events in log, $collected this round)
	# *
	# * This function updates the dad_sys_cis_imported table to reflect
	# * the most recent event processed in the $Logfile log on $System.
	#********************************************************/
	sub mark_log_processed
	{
	my $logfile = shift;
	my $system = shift;
	my $lastentry = shift;
	my $total = shift;
	my $collected = shift;
	my $next_launch = ((int(6000/($collected + 1))) * $Priority{$system});
	if($Priority{$system} < 3) 
	{ 
		$next_launch = ($next_launch > 120 ? 120 : $next_launch); 
	}
	$next_launch += mktime(localtime());
	if($lastentry > -1) 
	{
		&_SQL_Insert("UPDATE dad_sys_cis_imported SET LastLogEntry='$lastentry' WHERE Log_Name='$logfile' AND System_Name='$system'");}
		&_SQL_Insert("UPDATE dad_sys_event_import_from SET Next_Run='$next_launch' WHERE System_Name='$system'");
		&_SQL_Insert("INSERT INTO dad_sys_event_stats (System_Name,Service_Name, Stat_Type, Total_In_Log, Number_Inserted,Stat_Time) ".
			"VALUES ('$system', '$logfile', 1, $total, $collected, UNIX_TIMESTAMP(NOW()))");
	}

	sub ConvertSidToSidString{

	    my $sid  = shift;
		my $Revision, $SubAuthorityCount, $IdentifierAuthority0, $IdentifierAuthorities12, @SubAuthorities;
		my $IdentifierAuthority;
        $sid or return;
        ($Revision, $SubAuthorityCount, $IdentifierAuthority0, $IdentifierAuthorities12, @SubAuthorities) = unpack("CCnNV*", $sid);
        $IdentifierAuthority = $IdentifierAuthority0 ? sprintf('0x%04hX%08X', $IdentifierAuthority0, $IdentifierAuthorities12) : $IdentifierAuthorities12;
        $SubAuthorityCount == scalar(@SubAuthorities) or return;
        return "S-$Revision-$IdentifierAuthority-".join("-", @SubAuthorities);
    }
#
# End local functions
############################################################
$Win32::EventLog::GetMessageText = 0;	# If this is off, there should be no ntdll.dll calls!
	my $TotalEvents=0;
	my $who_am_i = shift;
	my $log;
	my @Logs = ();						#Logs to process from each system
	my %Service_IDs, %System_IDs;
	my $handle;							#Event log handle;
	my	$dsn, 							# Database connection
		$dbh;
	my $base, $recs, $newbase, $new, $results_ref, $hashRef,
		$row, @this_row, $total, $lastprocessed, $collected;
	my $system;
	my $stop_time, $continue;
	my %Record, @Values, $Value, $i;	
	my $logs_value;

	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Could not connect to DB server to for event thread $who_am_i.\n");
	$Status{"log $who_am_i"} = "Waiting";
	
	while((!$Time_To_Die))
	{
		$system="";
		while(!$system)
		{
			$system = $High_Priority_Queue->dequeue_nb();
			if(!$system) 
			{ 
				$system = $Process_Queue->dequeue_nb();
			}
			if(!$system)
			{
				sleep(1);
				if($Time_To_Die)
				{
				  $Status{"log $who_am_i"} = "Dead.";
				  return;
				}
			}
		}
		$logs_value = $LogThese{$system};
		$logs_value += 0;
		@Logs=();
		if($logs_value & 1) { unshift(@Logs, "Application");}
		if($logs_value & 2) { unshift(@Logs, "Security");}
		if($logs_value & 4) { unshift(@Logs, "System");}
		if($logs_value & 8) { unshift(@Logs, "DNS Server"); }
		if($logs_value & 16) { unshift(@Logs, "DHCP Server"); }
		if($logs_value & 32) { unshift(@Logs, "Directory Service"); }
		if($logs_value & 64) { unshift(@Logs, "File Replication Service"); }

		foreach $log (@Logs)
		{
			my $my_execution_time;
			if($Priority{$system} == 1)
			{
				$my_execution_time = 120;
			}
			if($Priority{$system} == 2)
			{
				$my_execution_time = $MAX_EXECUTION_TIME;
			}
			if($Priority{$system} == 3)
			{
				$my_execution_time = $MAX_EXECUTION_TIME * .8;
			}
			if($Priority{$system} > 3)
			{
				$my_execution_time = $MAX_EXECUTION_TIME * .6;
			}
			$stop_time = mktime(localtime())+$my_execution_time;
			$continue = 1;
			Win32::EventLog::Open($handle,$log, $system);
			if(!$handle)
			{ 
				print "Can't open $log EventLog on $system\n";
				&mark_log_processed($log, $system, -1, 0, 0);
				next; 	#Can't open log, go to the next one.
			}
# Figure out what our starting point is and how many records there are to read in.
			$base=$recs=$newbase=$new=0;
			{
				$handle->GetNumber($recs);
				$handle->GetOldest($base);
			}
			$new = $recs;
			$total = $base + $recs;
			$results_ref = &_SQL_Query("SELECT LastLogEntry FROM dad_sys_cis_imported WHERE Log_Name='$log' AND System_Name='$system'");
			$row = shift(@$results_ref);
			if($row)
			{
				$lastprocessed = @$row[0] + 0;
				if($total <= $lastprocessed) 
				{ 
					$handle->Close();
					&mark_log_processed($log, $system, $lastprocessed, 0, 0);
					next; 
				}
				if($lastprocessed < $base)
				{
					print "\t$who_am_i Missed ".($base-$lastprocessed)." events from $system!!  Catching up.\n";
					$base+=50;
				}
				else
				{
					$base = $lastprocessed;
				}
			$new = $total - $base;
			}
			else
			{
				print "\t\t* New Log\n";
				&_SQL_Insert("INSERT INTO dad_sys_cis_imported (Log_Name, System_Name, LastLogEntry) VALUES ('$log', '$system', '0')");
			}
# Set up for reading.  Position at one record before the actual base.
# And then read in all of the events.
			if($DEBUG) {print "\t\t\t$who_am_i:$system Processing $new events from $log log...\n";}
			{
#				lock($Event_Log_Lock);
				$continue = $handle->Read(EVENTLOG_FORWARDS_READ|EVENTLOG_SEEK_READ,
					$base, $hashRef);
			}
			while($continue)
			{
				$TotalEvents++;
				$Status{"log $who_am_i"} = "$system -> $log -> $TotalEvents -> $collected : $my_execution_time";
				$Record{"System"} = $system;
				$Record{"Service"} = $log;
				$Record{"TimeWritten"} = $hashRef->{"Timewritten"};
				$Record{"Source"} = $hashRef->{"Source"};
				$Record{"Category"} = $hashRef->{"Category"};
				$Record{"TimeGenerated"} = $hashRef->{"TimeGenerated"};
				$Record{"SID"} = &ConvertSidToSidString($hashRef->{"User"});
				$Record{"Computer"} = $hashRef->{"Computer"};
				$Record{"EventID"} = $hashRef->{"EventID"} & 0xffff;
				$Record{"EventType"} = $hashRef->{"EventType"};
				@Values = split(/\0/, $hashRef->{"Strings"});
				$i = 0;
				foreach $Value (@Values)
				{
					$Record{"Field_".($i)} = substr($Value, 0, 760);
					$i++;
				}


				if($Record{"EventID"} == 560 && $Record{"Field_1"} eq "File")
				{
					# 560 events need special handling to pull the file extension to field_25
					my @pieces;
					@pieces = split(/\./, $Record{"Field_2"});
					my $num_pieces = @pieces;
					if($num_pieces==1)
					{
						$Record{"Field_25"} = "";
					}
					else
					{
						$Record{"Field_25"} = substr($pieces[($num_pieces-1)], 0, $Field_Lengths[25]);
					}
				}

# Escape any special characters in the log
				foreach $Value (keys(%Record))
				{
					$Record{$Value} = addslashes($Record{$Value});
				}
				if(!$Filtered_Events{$Record{"EventID"}})
				{
					&record_event($Record{"System"}, $Record{"Service"}, $Record{"TimeWritten"}, $Record{"TimeGenerated"}, 
						$Record{"Source"}, $Record{"Category"}, $Record{"SID"}, $Record{"Computer"}, $Record{"EventID"}, $Record{"EventType"},
						($Record{"Field_0"}, $Record{"Field_1"}, $Record{"Field_2"}, $Record{"Field_3"}, 
						$Record{"Field_4"}, $Record{"Field_5"}, $Record{"Field_6"}, $Record{"Field_7"}, 
						$Record{"Field_8"}, $Record{"Field_9"}, $Record{"Field_10"}, $Record{"Field_11"},
						$Record{"Field_12"}, $Record{"Field_13"}, $Record{"Field_14"}, $Record{"Field_15"},
						$Record{"Field_16"}, $Record{"Field_17"}, $Record{"Field_18"}, $Record{"Field_19"},
						$Record{"Field_20"}, $Record{"Field_21"}, $Record{"Field_22"}, $Record{"Field_23"},
						$Record{"Field_24"}, $Record{"Field_25"}));
				}
				$base++;
				$collected++;
				$continue++;
				foreach $Value (keys(%hashRef)) { delete $hashRef{$Value}; }
				foreach $Value (keys(%Record)) { delete $Record{$Value}; }
				if((mktime(localtime()) > $stop_time) || ($Time_To_Die)) 
				{
					$continue = 0; 
				}
				else
				{
#					lock($Event_Log_Lock);
					$continue = $handle->Read(EVENTLOG_FORWARDS_READ|EVENTLOG_SEEK_READ,
						$base, $hashRef);
				}
			}
			$base--; #Subtract one since we read one too far.
			$handle->Close();
			&mark_log_processed($log, $system, ($base), $total, $collected);
#			print "\tThread $who_am_i finished processing $system:  $total, $collected\n";
			$total = 0;
			$collected = 0;
		}
	delete $Processing{$system};
	$Status{"log $who_am_i"} = "Waiting";
	}
print "\t$who_am_i Exited\n";
$Status{"log $who_am_i"} = "Dead.";
#delete $Status{"log $who_am_i"};
delete $Processing{$system};
return;
}

sub _insert_thread
{

	my $who_am_i = shift;
	my	$dsn, 						# Database connection
		$dbh;
	my 	$Queue_Size=0;
	my	$Inserted = 0;
	my $incoming;
	my $LocalQueue="";
	my $query;
	my $empty_loops = 0;
# Open the database connection.  We turn auto commit off so that we can do block inserts.
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Insert thread $who_am_i could not connect to database server.\n");
	$Status{"sql $who_am_i"} = "Waiting";
	$Queue_Size=0;
	if($DEBUG) { print "Exiting - Debug mode.  No inserts.\n"; return; }
	while(1)
	{
		my $Force=0;
		$incoming = $SQL_Queue->dequeue_nb();
		$empty_loops++;
		if($incoming)
		{
			$empty_loops=0;
			$_TotalQueries++;
			if($Queue_Size==0) { $LocalQueue = "$incoming"; }
			else {$LocalQueue .= ",$incoming";}
			$Inserted++;
			$Queue_Size++;
		}
		if(($SQL_Queue->pending() == 0) && ($Queue_Size > 0) && $Time_To_Die) { $Force=1; }
		if(($Queue_Size > $MAX_QUEUE_SIZE) || ($Force == 1) || $empty_loops > $MAX_IDLE_LOOPS) 
		{
			my $retries = 0;
			$empty_loops=0;
			$SQL = "INSERT INTO dad_sys_events (SystemID, ServiceID, TimeWritten, TimeGenerated, Source, Category, SID, ".
			"Computer, EventID, EventType, Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, Field_6, Field_7, Field_8, Field_9, ".
			"Field_10, Field_11, Field_12, Field_13, Field_14, Field_15, Field_16, Field_17, ".
			"Field_18, Field_19, Field_20, Field_21, Field_22, Field_23, Field_24, Field_25, ".
			"idxID_Code, idxID_Kerb, idxID_NTLM) ".
			"VALUES ".$LocalQueue;
			$continue = 0;
			if($LocalQueue eq "") { $continue = 1; }
			while(! $continue)
			{
				$retry++;
				if(! $Groomer_Running)
				{
					$query=$dbh->prepare($SQL);
					$query->execute(); 
					if($DBI::err)
					{
						my $err, $errstr;
						$err = $DBI::err;
						$errstr = $DBI::errstr;
						print "DBI Error:  $err $errstr\n";
						print "Retrying in three seconds.\n";
						$dbh->disconnect();
						sleep(3);
						$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD");
						if($retry>3)  #Error 3 times occured, keep going
						{
							$continue=1; 
							open(FILE, ">>AggregateErrors.log");
							flock(FILE,2);
							print FILE "DBI Error $err - $errstr\n";
							flock(FILE,8);
							close(FILE);
							&_spew_sql($SQL);
						}
					}
					else 
					{ 
						$continue = 1; 
					}
				}
				else
				{
					&_spew_sql($SQL);
					$continue = 1;
				}
				if(!$Groomer_Running)
				{
					$query->finish();
				}
			}
			
			$Queue_Size = 0;
			$LocalQueue="";
		}
		$Status{"sql $who_am_i"} = "Queue size: $Queue_Size  Inserted: $Inserted";
		if(($Queue_Size==0) && ($SQL_Queue->pending() == 0) && ($Time_To_Die==1))
		{ 
			$Status{"sql $who_am_i"} = "Dead.";
#			delete($Status{"sql $who_am_i"});
			return; 
		}
		if(!$incoming) {sleep(5);}
	}
	$Status{"sql $who_am_i"} = "Died mysteriously.";
}

sub _spew_sql
{
	my $SQL;
	$SQL = shift();
	open(FILE, ">>SQL_Contents.log");
	flock(FILE,2);
	print FILE "$SQL;\n";
	flock(FILE,8);
	close(FILE);
}

#########################
# Starts all of the processing threads
sub _start_threads
{
	print "Starting threads ($INSERT_THREADS, $EVENT_HANDLER_THREADS):\n";
	for(my $i=0;$i!=$INSERT_THREADS;$i++)
	{
		my $thread;

		$thread = threads->new(\&_insert_thread, $i);
		$Insert_Threads{$i} = $thread;
		$thread->detach();
	}
	print "\tInsert threads started: $INSERT_THREADS.\n";
	for(my $i=0;$i!=$EVENT_HANDLER_THREADS;$i++)
	{
		my $thread;
		$thread = threads->new(\&_event_thread, $i);
		$Log_Threads{$i} = $thread;
		$thread->detach();		
	}
	print "\tEvent handlers started: $EVENT_HANDLER_THREADS.\n";
}

##########################
# Grabs the names of systems ripe for processing
sub _get_systems_to_process
{
	my	$results_ref,				# Used to hold query responses
		$row,						#Row array reference
		@this_row;					#Current row
	my	$dsn, 						# Database connection
		$dbh;
	my @Systems;
	
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Could not connect to DB server to import the list of servers to poll.\n");

	# Fetch the names of the systems to poll.  To add a system simply add its name to the dad_sys_event_import table. 
	# There is no need to restart this process to pick up the new system names or remove old names.
	$results_ref = &SQL_Query("SELECT System_Name,Priority,Next_Run,Log_These FROM dad_sys_event_import_from ORDER BY Priority DESC");
	# Populate the @Systems array
	while($row = shift(@$results_ref) ) 
	{
		@this_row = @$row;
		if(mktime(localtime()) > $this_row[2]) 
			{
				unshift(@Systems, $this_row[0]);
				$LogThese{$this_row[0]} = $this_row[3];
				$Priority{$this_row[0]} = $this_row[1];
			}
	}
	return(@Systems);
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

##################################################
#
# SQL_Insert - Does the legwork for all SQL inserts including basic error checking
# 	Takes a SQL string as an argument
#
##################################################
sub SQL_Insert
{
	my $SQL = $_[0];
	my $query = $dbh->prepare($SQL);
	if($DEBUG){return; print"$SQL\n";return;}
	$query -> execute();
	$query->finish();
}

##################################################
#
# SQL_Batch_Insert - Does the legwork for all SQL inserts including basic error checking
# 	Takes a SQL string as an argument
#
##################################################
sub SQL_Batch_Insert
{
	$_TotalQueries++;
	$SQL = $_[0];
	if($DEBUG)
	{ return;
		print"$SQL\n";
		$_TotalQueries=0;
		return;
	}
	$dbh->do($SQL);
}

sub _build_stats
{
	my $system;
	my %ALog_Size, %AInserted, %Log_Size, %Inserted;
	my @Systems;					#Systems to process
	@Systems = &_get_stats_to_process();

	foreach $system(@Systems)
	{
		my $size, @times, $i;
		my $log_change, $inserted, $insert_ratio;
		my @Times, @Logged, @Inserted, $this_time;
	
		$insert_ratio = 0;
		&_get_system_stat_data($system,\%Log_Size,\%Inserted, \%ALog_Size, \%AInserted, "Security", $Stat_Time_Period);
		@times = reverse(sort(keys(%Log_Size)));
		$size=@times;
	
		foreach $i (0..($size))
		{
			$log_change = $Log_Size{$times[$i]};
			$inserted = $Inserted{$times[$i]};
			$this_time = &_get_time_string($times[$i]);
			unshift(@Times, $this_time);
			unshift(@Logged, $log_change);
			unshift(@Inserted, $inserted);
			if($inserted < 0) {print "$system: $this_time Logged - $log_change  Inserted - $inserted  Difference - $insert_ratio\n";}
		}
		my $points = @Times;
		if($points)
		{
			my $graph = GD::Graph::lines->new(400, 100);
			$graph->set( 
				title				=> "$system Event/Insert Rate",
				x_label_position	=> 0.5,
				line_width			=> 1,
				x_label_skip		=> int($points/10),
				x_labels_vertical	=> 1
			) or die $graph->error;
			my @Data=([@Times],[@Logged],[@Inserted]);#,[@Insert_Ratio]);
			$graph->set_title_font('/fonts/arial.ttf', 24);
			my $gd = $graph->plot(\@Data) or die $graph->error;
			open(IMG, '>'.$OUTPUT_LOCATION."/$system.gif") or die $!;
			binmode IMG;
			print IMG $gd->gif;
			close IMG;
		}
		@Times=();
		@Logged=();
		@Inserted=();
		@Insert_Ratio=();
		%Log_Size = ();
		%Inserted = ();
	}
	print "Generating aggregate.\n";
	@Times=();
	@Logged=();
	@Inserted=();
	@Insert_Ratio=();
	@times=();
	@Data=();
	%ALog_Size = ();
	%AInserted = ();
	foreach $system (@Systems)
	{
		&_get_aggregate_system_stat_data($system,\%Log_Size,\%Inserted, \%ALog_Size, \%AInserted, "Security", time());
		#Previous line gathers all aggregate data for all time
	}
	@times = reverse(sort(keys(%ALog_Size)));
	$size=@times;
	foreach $i (0..($size))
	{
		$log_change = $ALog_Size{$times[$i]};
		$inserted = $AInserted{$times[$i]};
		$this_time = &_get_time_string($times[$i],1);
		unshift(@Times, $this_time);
		unshift(@Logged, $log_change);
		unshift(@Inserted, $inserted);
		if($inserted < 0) {print "$system: $this_time Logged - $log_change  Inserted - $inserted  Difference - $insert_ratio\n";}
		#print "$system: $this_time Logged - $log_change  Inserted - $inserted  Difference - $insert_ratio\n";
	}
	
	#Print Aggregate
	my $points = @Times;
	my $graph = GD::Graph::lines->new(400,200);
	$graph->set( 
		title				=> "$system Event/Insert Rate",
		x_label_position	=> 0.5,
		line_width			=> 1,
		x_label_skip		=> int($points/10),
		x_labels_vertical	=> 1
	) or die $graph->error;
	my @Data=([@Times],[@Logged],[@Inserted]);#,[@Insert_Ratio]);
	$graph->set_title_font('/fonts/arial.ttf', 24);
	my $gd = $graph->plot(\@Data) or die $graph->error;
	open(IMG, '>'.$OUTPUT_LOCATION.'/Aggregate.gif') or die $!;
	binmode IMG;
	print IMG $gd->gif;
	close IMG;
	return;

sub _get_time_string
{
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime(shift);
	my$year = 1900 + $yearOffset;
	my $theTime;
	if(shift())
	{
		$theTime = ($month+1)."/".($dayOfMonth+1);
	}
	else
	{
		$theTime = ($hour<10 ? "0$hour" : "$hour").":".($minute<10? "0$minute" : "$minute");
	}
	return $theTime; 
}
##########################
# Grabs the raw data for each system.
sub _get_system_stat_data
{
	my	$results_ref,				# Used to hold query responses
		$row,						#Row array reference
		@this_row;					#Current row
	my $system, $Log_Size, $Inserted, $ALog, $AInserted, $Service;
	my $Time_Period;
	($system,$Log_Size,$Inserted, $ALog, $AInserted, $Service, $Time_Period)=@_ or die("Incorrect arguments to _get_system_stat_data.\n");
	
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Could not connect to DB server to import the list of servers to poll.\n");

	$Time_Period = time()-$Time_Period;
	my $SQL = "SELECT Total_In_Log,Number_Inserted,Stat_Time,Service_Name FROM dad_sys_event_stats WHERE Service_Name='$Service' AND System_Name='$system' AND Stat_Time>$Time_Period ORDER BY Stat_Time";
	$results_ref = &SQL_Query($SQL);
	my $last_logged = -1;
	while($row = shift(@$results_ref) ) 
	{
		@this_row = @$row;
		my $this_time = $this_row[2];
		$this_time = int($this_time/600) * 600;
		if($this_row[0] > 0)
		{
			my $log_change = 0;
			if($last_logged != -1)
				{$log_change = $this_row[0] - $last_logged};
			$Log_Size->{$this_time} += $log_change;
			$last_logged = $this_row[0];
			$Inserted->{$this_time} += $this_row[1];
			$ALog->{$this_time} += $log_change;
			$AInserted->{$this_time} += $this_row[1];
		}
	}
	return;
}

##########################
# Grabs the raw data for each system.
sub _get_aggregate_system_stat_data
{
	my	$results_ref,				# Used to hold query responses
		$row,						#Row array reference
		@this_row;					#Current row
	my $system, $Log_Size, $Inserted, $ALog, $AInserted, $Service;
	my $Time_Period;
	($system,$Log_Size,$Inserted, $ALog, $AInserted, $Service, $Time_Period)=@_ or die("Incorrect arguments to _get_system_stat_data.\n");
	
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Could not connect to DB server to import the list of servers to poll.\n");

	$Time_Period = time()-$Time_Period;
	my $SQL = "SELECT Total_In_Log,Number_Inserted,Stat_Time,Service_Name FROM dad_sys_event_stats WHERE Service_Name='$Service' AND System_Name='$system' AND Stat_Time>$Time_Period ORDER BY Stat_Time";
	$results_ref = &SQL_Query($SQL);
	my $last_logged = -1;
	while($row = shift(@$results_ref) ) 
	{
		@this_row = @$row;
		my $this_time = $this_row[2];
		$this_time = int($this_time/86400) * 86400;
		if($this_row[0] > 0)
		{
			my $log_change = 0;
			if($last_logged != -1)
				{$log_change = $this_row[0] - $last_logged};
			$last_logged = $this_row[0];
			$ALog->{$this_time} += $log_change;
			$AInserted->{$this_time} += $this_row[1];
		}
	}
	return;
}


##########################
# Grabs the names of systems ripe for processing
sub _get_stats_to_process
{
	my	$results_ref,				# Used to hold query responses
		$row,						#Row array reference
		@this_row;					#Current row
	my @Systems;
	

	# Fetch the names of the systems to poll.  To add a system simply add its name to the dad_sys_event_import table. 
	# There is no need to restart this process to pick up the new system names or remove old names.
	$results_ref = &SQL_Query("SELECT DISTINCT System_Name FROM dad_sys_event_stats");
	# Populate the @Systems array
	while($row = shift(@$results_ref) ) 
	{
		@this_row = @$row;
		unshift(@Systems, $this_row[0]);
	}
	return(@Systems);
}
}

sub _check_for_groomer
{
	my $now, $hours, $that_hour, $that_minute, $minutes;

	if($Pending_Running) { return 0; } # Don't groom if you're still catching up.
	$now = time();
	$minutes = $now/(60);
	$hours = $minutes/(60);
	$that_hour = ($hours % 24) - $TZ_Offset;
	$that_minute = $minutes % 60;
	if(($Groomer_Hour == $that_hour) && ($that_minute < 1))
	{
		return 1;
	}
	return 0;
}

sub _groomer
{
	my $days_of_history=31*24*60*60; #31 days of history
	my @Events_To_Prune;
	my %Explanations, %Retention_Times;
	
	$Groomer_Running = 1;
	print "Groomer running.\n";
	&_get_events_to_prune();
	
	foreach $event (@Events_To_Prune)
	{
		&_prune_events($event);
	}
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
	
		print "Pruning statistics\n";
	
		my $mark = time()-$days_of_history;
		$SQL = "DELETE FROM dad_sys_events_groomed WHERE Timestamp<$mark";
		print "Executing $SQL\n";
		my $start_time = time();
		if($DEBUG!=1) { $deleted = (($dbh->do($SQL)) * 1); } else { $deleted=0; }
		print "Deleted $deleted rows.  Pruning took ".(time()-$start_time)." seconds.\n";
		$SQL = "DELETE FROM dad_sys_event_stats WHERE Stat_Time<$mark";
		print "Executing $SQL\n";
		my $start_time = time();
		if($DEBUG!=1) { $deleted = (($dbh->do($SQL)) * 1); } else { $deleted=0; }
		print "Deleted $deleted rows.  Pruning took ".(time()-$start_time)." seconds.\n";
		print "Optimizing table to remove holes.\n";
		my $start_time = time();
		$SQL = "OPTIMIZE TABLE dad_sys_event_stats";
		$dbh->do($SQL);
		print "Table optimized.  Optimization took ".(time()-$start_time)." seconds.\n";
	}
	
	
	sub _prune_events
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
		my	$dsn, 						# Database connection
			$dbh;
		my $event_to_prune = shift();
		
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server to groom.\n");

		my $start_time = time();
			
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
			
		$SQL = "RENAME TABLE dad_sys_events TO dad_tmp, dad_sys_events_pruning TO dad_sys_events, dad_tmp TO dad_sys_events_pruning";
		$dbh->do($SQL) or die("Could not rename tables for groomer.");
		
		foreach $event (@Events_To_Prune)
		{
			if($event == 0) { next; } # Don't try to process default rule
			print "Pruning event ID $event\n";
			$SQL = "INSERT INTO dad_sys_events SELECT * FROM dad_sys_events_pruning WHERE EventID='$event' AND TimeGenerated>".(time() - $Retention_Times{$event});
			my $query = $dbh->prepare($SQL);
			$query->execute() or die("Error pruning!  Could not complete prune for $event.");
			$query->finish();
		}
		print "Pruning default rule\n";
		$SQL = "INSERT INTO dad_sys_events SELECT * FROM dad_sys_events_pruning WHERE TimeGenerated>".(time()-$Retention_Times{0});
		foreach $event (@Events_To_Prune)
		{
			if($event == 0)
			{
				next;
			}
			$SQL .= " AND NOT EventID='$event'";
		}
		my $query = $dbh->prepare($SQL);
		$query->execute() or die("Error pruning!  Could not complete default rule.");
		$query->finish();
		print "Pruning Complete.  Pruning took ".(time()-$start_time)." seconds.\n";
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

sub _insert_pending_events
{
	my $pending = 1;
	open(QUERIES, $BackupSQLFile) or $pending = 0;
	close(QUERIES);
	if($pending)
	{
		my $thread;
		rename($BackupSQLFile, "$BackupSQLFile.pnd") or system("mv", $old, $new);
		$thread = threads->new(\&_pending_inserts_thread);	#Spin and detach a groomer thread
		$thread->detach();
	}
}

sub _pending_inserts_thread
{
	my	$dsn, 						# Database connection
		@dbh,
		$query,
		$connection;
	
	$Pending_Running = 1;
	open(QUERIES, "$BackupSQLFile.pnd");
	print "Found pending SQL statements.  Loading now.\n";
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	for($connection=0; $connection != 10; $connection++)
	{
		$dbh[$connection] = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Pending SQL Inserter could not connect to database server.\n");
	}
	$connection=0;
	my $num_queries = 0;
	while (<QUERIES>)
	{
		$num_queries++;
		chomp();
		$query=$dbh[$connection%10]->prepare($_);
		$query->execute();
		$query->finish();
		$connection++;
		if($num_queries%1000==0) { print "$num_queries processed.\n"; }
	}
	for($connection=0; $connection != 10; $connection++)
	{
		$dbh[$connection]->disconnect();
	}
	close(QUERIES);
	unlink("$BackupSQLFile.pnd");
	print "Processed $num_queries pending SQL inserts.\n";
	$Pending_Running = 0;
}
