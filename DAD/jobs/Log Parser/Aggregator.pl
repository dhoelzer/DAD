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
use Time::Local;
#use Thread eval;
# Modules for DB and Event logs.  POSIX is required for Unix time stamps
use DBI;
use POSIX;
use Win32::EventLog;

################################################################
#
# The following are "Shared".  This means that all threads can see the contents or modify the contents of these
my $Time_To_Die : shared;		# Windows threads has a nasty memory leak.  This is used to force
								# all threads to exit and then to die gracefully.
my $Events_ID_DB : shared;
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
my $Log_File_Queue : shared;
my $SQL_Queue : shared;			#Queue used to transfer inserts to insert threads
my $Process_Queue : shared;		#Queue used to mark next logs to process
my $High_Priority_Queue : shared; #Queue used for priority 1 systems
my $MAX_EXECUTION_TIME : shared;#Maximum time a thread can spend processing any given log.
my %Unique_Strings : shared;	#In memory unique strings
my $GET_UNIQUE_LOCK : shared;	#Used to lock SQL access for unique string processing.
my $Hash_hits : shared;
my $Late_Hash_hits : shared;
my $Hash_Lookups : shared;
my $Hash_Inserts : shared;
my $Hash_Size : shared;
$Hash_hits = 0;
$Events_ID_DB=-1;
##################################################################

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
my	$dsn, 						# Database connection
	$dbh;

#Read in and evaluate the configuration values
open(FILE,"Aggregator.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

	
$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to import the list of servers to poll.\n");

#Initialize shared variables
$Time_To_Die = 0;
$Pending_Running = 0;

# Create the queues.  These queues are used to transfer servers to the event queues and events to the SQL queues.
$SQL_Queue = Thread::Queue->new;
$Process_Queue = Thread::Queue->new;
$Log_File_Queue = Thread::Queue->new;
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
	
	$loop++;					# Number of times through this run
#	$Time_Remaining = $Total_Run_Time - (mktime(localtime())- $System_Started);
	$Time_Remaining = "Continuously running.";
	{
		#Recreate the quick stats every time through.
		open(STATS, ">$OUTPUT_LOCATION/stats2.html") or print "Couldn't open stats file.\n";
		print STATS<<End;
		<html>
		<head>
		<title>Aggregator Status</title>
		<meta http-equiv="Refresh" CONTENT="30;URL=/stats/stats2.html" />
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
		print STATS "Hash hits: $Hash_hits<br>\n";
		print STATS "Strings in Hash: ".$Hash_Size."<br>\n";
		print STATS "<hr />";
		if($Pending_Running)
		{
			print STATS "Inserting outstanding queries.\n";
		}
		close(STATS);
	}
							#See which queues are waiting and queue them as appropriate
	@Systems=();
	if($SQL_Queue->pending() < 25000)
	{
		@Systems = &_get_systems_to_process;
	}
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
	if(($loop-1)%10 == 0)
	{
		if($Output){print "Grabbing log paths\n";}
		@logfiles = &Get_Unprocessed_Log_Paths($LOG_LOCATION);
		if($Output){print "Processing logs:\n";}
		foreach $log (@logfiles)
		{
			if($Output){print "\tProcessing: $log\n";}
			$Log_File_Queue->enqueue($log);
		}
		undef(@logfiles);
	}

	sleep(60);				# Time between interations
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
	my	$dsn, 						# Database connection
		$dbh;
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Could not connect to DB server to update filtered event list.\n");

	##################################################
	#
	# record_event - Push the event into the database
	# Takes as arguments the timestamp, reporting system, service followed by an array of fields
	# Maintains the %System_IDs and %Service_IDs hashes
	#
	##################################################
	sub record_event
	{
		$SQL_Queue->enqueue(join('~~~~~',@_));
	}

	#########################
	# Populates the filtered events hash
	sub _get_filtered_events
	{
		my	$results_ref,				# Used to hold query responses
			$row,						#Row array reference
			@this_row;					#Current row
	# Open the database connection.  We turn auto commit off so that we can do block inserts.
	
		%Filtered_Events;
	# Fetch the list of services to filter
		$results_ref = &SQL_Query("SELECT Event_ID, Description FROM dad_sys_filtered_events");
		while($row = shift(@$results_ref))
		{
			@this_row = @$row;
			$Filtered_Events{$this_row[0]}=1;
		}
		undef $results_ref;
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
		&SQL_Insert("UPDATE dad_sys_cis_imported SET LastLogEntry='$lastentry' WHERE Log_Name='$logfile' AND System_Name='$system'");
		&SQL_Insert("UPDATE dad_sys_event_import_from SET Next_Run='$next_launch' WHERE System_Name='$system'");
		&SQL_Insert("INSERT INTO dad_sys_event_stats (System_Name,Service_Name, Stat_Type, Total_In_Log, Number_Inserted,Stat_Time) ".
			"VALUES ('$system', '$logfile', 1, $total, $collected, UNIX_TIMESTAMP(NOW()))");
		}
	}

#
# End local functions
############################################################

	$Win32::EventLog::GetMessageText = 0;	# If this is off, there should be no ntdll.dll calls!
	# We've discovered that NTDLL.dll is -not- thread safe.  If you turn this back on, expect your aggregator
	# to die horribly.
	
	my $TotalEvents=0;
	my $who_am_i = shift;
	my $log;
	my @Logs = ();						#Logs to process from each system
	my %Service_IDs, %System_IDs;
	my $handle;							#Event log handle;
	my $base, $recs, $newbase, $new, $results_ref, $hashRef,
		$row, @this_row, $total, $lastprocessed, $collected;
	my $system;
	my $stop_time, $continue;
	my %Record, @Values, $Value, $i;	
	my $logs_value;
	my $Total_Sleep=0;

	$Status{"log $who_am_i"} = "Waiting";
	
	while((!$Time_To_Die))
	{
		$system="";
		while($SQL_Queue->pending() > 100000)
		{
			$Status{"log $who_am_i"} = "Pausing.. More than 100,000 inserts pending.";
			sleep(15);
		}
		while(!$system)
		{
			$system = $High_Priority_Queue->dequeue_nb();
			if(!$system) 
			{ 
				$system = $Process_Queue->dequeue_nb();
			}
			if(!$system)
			{
				$Total_Sleep+=30;
				$Status{"log $who_am_i"} = "Sleeping: $Total_Sleep";
				sleep(30);
				if($Time_To_Die)
				{
				  $Status{"log $who_am_i"} = "Dead.";
				  return;
				}
				if($Total_Sleep > 600) { &SQL_Query("SELECT 1"); $Total_Sleep=0;}
			}
		}
		$Total_Sleep=0;
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
			$handle = Win32::EventLog->new($log, $system) or $continue=0;
			if(!$continue)
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
			$results_ref = &SQL_Query("SELECT LastLogEntry FROM dad_sys_cis_imported WHERE Log_Name='$log' AND System_Name='$system'");
			$row = shift(@$results_ref);
			if($row)
			{
				$lastprocessed = @$row[0] + 0;
				if($total > 0 && $lastprocessed > $total)
				{
# If a Windows log is cleared, the internal event numbers are reset.  This looks for this behavior.
					print "\nLikely log reset on $system, $log log.  Forcing pull.\n";
					$lastprocessed = $base;
				}
				if($total <= $lastprocessed) 
				{ 
					$handle->Close();
					&mark_log_processed($log, $system, $lastprocessed, 0, 0);
					next; 
				}
				$base = $lastprocessed;
				$new = $total - $base;
			}
			else
			{
				print "\t\t* New Log\n";
				&SQL_Insert("INSERT INTO dad_sys_cis_imported (Log_Name, System_Name, LastLogEntry) VALUES ('$log', '$system', '0')");
			}
# Set up for reading.  Position at one record before the actual base.
# And then read in all of the events.
			if($DEBUG) {print "\t\t\t$who_am_i:$system Processing $new events from $log log...\n";}
			{
# Sometimes, when the log has wrapped, the logs will advance faster than we can read them off.  Here we loop until we find an event
# that exists.  Since touching the event log generates events itself, we'll jump ahead 50 events at a time.
				$continue = $handle->Read(EVENTLOG_FORWARDS_READ|EVENTLOG_SEEK_READ,
					$base, $hashRef);
				while (!$continue && $base < $total)
				{
					$handle->GetOldest($base);
					$base+=50;
					$continue = $handle->Read(EVENTLOG_FORWARDS_READ|EVENTLOG_SEEK_READ,
					$base, $hashRef);
				}
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
						$Record{"Field_25"} = substr($pieces[($num_pieces-1)], 0, 10);
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
					$continue = $handle->Read(EVENTLOG_FORWARDS_READ|EVENTLOG_SEEK_READ,
						$base, $hashRef);
				}
			}
			$base--; #Subtract one since we read one too far.
			$handle->Close();
			&mark_log_processed($log, $system, ($base), $total, $collected);
			$total = 0;
			$collected = 0;
			undef %hashRef;
			undef %Record;
			undef $handle;
		}
	delete $Processing{$system};
	$Status{"log $who_am_i"} = "Waiting";
	}
print "\t$who_am_i Exited\n";
$Status{"log $who_am_i"} = "Dead.";
delete $Processing{$system};
return;
}

sub __Get_Unique_ID_Or_Insert
{
	my $String_ID,$result_ref, $rows_returned, $this_string;
	
	$this_string = shift;

	# First double check memory hash in case it was added while we were locked.
	if($Unique_Strings{"$this_string"})
	{
		$Hash_hits ++;
		$Late_Hash_hits ++;
		return $Unique_Strings{"$this_string"};
	}

	$result_ref = &SQL_Query("SELECT String_ID FROM event_unique_strings WHERE String = '$this_string'");
	$rows_returned = scalar @$result_ref;
	if($rows_returned < 1)
	{
		$Hash_Inserts++;
		#print "Inserting: $this_string\n";
		&SQL_Insert("INSERT INTO event_unique_strings (String) VALUES ('$this_string')");
		$result_ref = &SQL_Query("SELECT String_ID FROM event_unique_strings WHERE String = '$this_string'");
		$rows_returned = scalar @$result_ref;
		if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new string!\n"); }
	}
	else
	{
		$Hash_Lookups++;
	}
	$row = shift(@$result_ref);
	$String_ID= @$row[0];
	$Unique_Strings{"$this_string"} = $String_ID;
	$Hash_Size++;
	return $String_ID;
}

sub Get_Unique_ID
{
	my $String_ID;
	my $this_string;

	$this_string = shift;
	if($Unique_Strings{"$this_string"})
		{
			$Hash_hits ++;
			return $Unique_Strings{"$this_string"};
		}
	lock $GET_UNIQUE_LOCK;
	$String_ID = &__Get_Unique_ID_Or_Insert($this_string);
	if($Hash_Size > $MAX_UNIQUE_STRINGS)
		{
			print "Clearing strings hash: ".scalar(keys(%Unique_Strings))."\n";
			%Unique_Strings = ();
			$Hash_Size = 0;
		}
	return $String_ID;
}

sub Get_Block
{
	my $New_Block_Start;
	my $Event_ID;
	
	lock $Events_ID_DB;
	if($Events_ID_DB == -1)
	{
		print "Inserting marker event\n";
		$Event_ID=&SQL_Insert("INSERT INTO events (Time_Written, Time_Generated, System_ID, Service_ID) VALUES ".
			"(UNIX_TIMESTAMP(NOW()), (UNIX_TIMESTAMP(NOW())), 0, 0)");
		$Events_ID_DB = $Event_ID;
	}
	$New_Block_Start = ++$Events_ID_DB;
	$Events_ID_DB+= ($BLOCK_SIZE + 2);
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
	my $Event_ID;
	my $Block_Pos, $Block_End;

	$Block_End=0;
	$Block_Pos=1;
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or die ("Insert thread $who_am_i could not connect to database server.\n");
	$Status{"sql $who_am_i"} = "Waiting";
	$Queue_Size=0;
	my $InsertString="";
	if($DEBUG) { print "Exiting - Debug mode.  No inserts.\n"; return; }
	while(1)
	{
		my $Force=0;
		$incoming = $SQL_Queue->dequeue_nb();
		if($incoming)
		{
			$_TotalQueries++;
			my $time, $system, $service, @values, @row, $row, $result_ref, $rows_returned;
			($system, $service, $timewritten, $timegenerated, @values) = split(/~~~~~/,$incoming);
			
			# See if the service is known.  If not, get it from the database or create a new ID:
			if(! $Service_IDs{"$service"})
			{
				$result_ref = &SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
				$rows_returned = scalar @$result_ref;
				if($rows_returned < 1)
				{
					&SQL_Insert("INSERT INTO dad_sys_services (Service_Name) VALUES ('$service')");
					$result_ref = &SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
					$rows_returned = scalar @$result_ref;
					if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (service)!\n"); }
				}
				$row = shift(@$result_ref);
				$Service_IDs{"$service"} = @$row[0];
				undef $result_ref;
			}
		
			# See if the system is known.  If not, get it from the database or create a new ID:
			if(! $System_IDs{"$system"})
			{
				$result_ref = &SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
				$rows_returned = scalar @$result_ref;
				if($rows_returned < 1)
				{
					&SQL_Insert("INSERT INTO dad_sys_systems (System_Name) VALUES ('$system')");
					$result_ref = &SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
					$rows_returned = scalar @$result_ref;
					if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (system)!\n"); }
				}
				$row = shift(@$result_ref);
				$System_IDs{"$system"} = @$row[0];
				undef $result_ref;
			}
			if($Block_Pos >= $Block_End)
			{
				$Block_Pos = &Get_Block();
				$Block_End = $Block_Pos + $BLOCK_SIZE;
			}
			$Event_ID = $Block_Pos++;
			if($Bulk_Event_Insert eq "")
			{
				$Bulk_Event_Insert = "($Event_ID,UNIX_TIMESTAMP(NOW()), $timegenerated, ".
					$System_IDs{"$system"}.", ". $Service_IDs{"$service"}.")";
			}
			else
			{
				$Bulk_Event_Insert .= ",($Event_ID,UNIX_TIMESTAMP(NOW()), $timegenerated, ".
					$System_IDs{"$system"}.", ". $Service_IDs{"$service"}.")";
			}
			$StringToInsert="";
			$StringToInsert .= " $_" foreach(@values);
			$StringToInsert =~ s/([\[\]{},'"<>\@:#()=])/ $1 /g;
			$StringToInsert =~ s/\\/\//g;
			$StringToInsert =~ s/  / /g;
			$StringToInsert =~ s/ ['"] / /g;
			@insert_strings = split(/ /,$StringToInsert);
			$Queue_Size++;
			my $string_position=0;
			foreach(@insert_strings)
			{
				s/(['"])//g;
				$value = substr($_, 0, 766);
				$String_ID = &Get_Unique_ID($value);
				if($InsertString eq "")
				{
					$InsertString = "($Event_ID, $string_position, $String_ID)";
				}
				else
				{
					$InsertString .= ",($Event_ID, $string_position, $String_ID)";
				}
				$string_position++;
				undef $result_ref;
			}
		}
		if(($Queue_Size > $MAX_QUEUE_SIZE) || (($SQL_Queue->pending() == 0) && ($Queue_Size>0) && ($empty_loops>$MAX_IDLE_LOOPS)))
		{
			$empty_loops = 0;
			$Inserted += $Queue_Size;
#print "$InsertString\n\n$Bulk_Event_Insert\n";
			&SQL_Insert("INSERT DELAYED INTO event_fields (Events_ID, Position, String_ID) VALUES ".$InsertString);
			&SQL_Insert("INSERT DELAYED INTO events (Events_ID,Time_Written, Time_Generated, System_ID, Service_ID) VALUES $Bulk_Event_Insert");
			undef $InsertString;
			undef $Bulk_Event_Insert;
			$Queue_Size = 0;
		}
		$Status{"sql $who_am_i"} = "Queue size: $Queue_Size  Inserted: $Inserted";
		if(($Queue_Size==0) && ($SQL_Queue->pending() == 0) && ($Time_To_Die==1))
		{ 
			$Status{"sql $who_am_i"} = "Dead.";
#			delete($Status{"sql $who_am_i"});
			return; 
		}
		if(!$incoming)
		{
			$empty_loops ++;
			if($empty_loops > $MAX_IDLE_LOOPS && $Queue_Size == 0)
			{
				$Status{"sql $who_am_i"} = "Sleeping";
				sleep(15);
				$empty_loops = 0;
			}
		}
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
	my $i;
	print "Starting threads ($INSERT_THREADS, $EVENT_HANDLER_THREADS):\n";
	for($i=0;$i!=$INSERT_THREADS;$i++)
	{
		my $thread;

		$thread = threads->new(\&_insert_thread, $i);
		$Insert_Threads{$i} = $thread;
		$thread->detach();
	}
	print "\tInsert threads started: $INSERT_THREADS.\n";
	for($i=0;$i!=$EVENT_HANDLER_THREADS;$i++)
	{
		my $thread;
		$thread = threads->new(\&_event_thread, $i);
		$Log_Threads{$i} = $thread;
		$thread->detach();		
	}
	$i++;
	$thread = threads->new(\&_log_thread, $i);
	$Log_Threads{$i} = $thread;
	$thread->detach();
	print "\tEvent handlers started: $EVENT_HANDLER_THREADS.\n";
}

##########################
# Grabs the names of systems ripe for processing
sub _get_systems_to_process
{
	my	$results_ref,				# Used to hold query responses
		$row,						#Row array reference
		@this_row;					#Current row
	my @Systems;

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
	undef $results_ref;
	undef $row;
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
	eval
	{
		$query -> execute() or die("$SQL\n");
	};
	if($@){
		print "Caught error: $@\n";
		undef $dsn;
		undef $dhb;
		$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
		$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
			or die ("Could not connect to DB server\n");
		$query->execute();
	};
	my $ref_to_array_of_row_refs = $query->fetchall_arrayref() or die("$SQL\n"); 
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
	my $in_id = $dbh->{ q{mysql_insertid}};
	$query->finish();
	undef $query;
	return $in_id;
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

sub _insert_pending_events
{
	my $pending = 1;
	open(QUERIES, $BackupSQLFile) or $pending = 0;
	close(QUERIES);
	if($pending)
	{
		my $thread;
		rename($BackupSQLFile, "$BackupSQLFile.pnd") or system("mv", $old, $new);
		$thread = threads->new(\&_pending_inserts_thread);	#Spin and detach an inserter thread
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

sub addslashes
{
	my $String = shift;
	$String =~ s/(["'\%\\])/\\\1/g;
	$String =~ s/[^[:print:]]//g;
	return $String;
}

sub _log_thread
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
		$SQL_Queue->enqueue(join('~~~~~',@_));
	}

	sub move_log_processed
	{
		my $logfile = shift;
		$newname = $logfile;
		$newname =~ s/.*\/(.*)/$1/;
		rename($logfile, $LOG_PROCESSED_LOCATION."/$newname") or die("Could not move processed log $newname!\n");
	}

#
# End local functions
############################################################
	my $who_am_i = shift;

	$Status{"log $who_am_i"} = "Waiting";
	
	while((!$Time_To_Die))
	{
		$log="";
		while(!$log)
		{
			$log = $Log_File_Queue->dequeue_nb();
			if(!$log)
			{
				$Total_Sleep+=5;
				$Status{"log $who_am_i"} = "Sleeping: $Total_Sleep";
				sleep(5);
				if($Time_To_Die)
				{
				  $Status{"log $who_am_i"} = "Dead.";
				  return;
				}
			}
			else
			{
			my	$line, 						# Temp var for lines being processed
				$logfile, 					# Path to log file being processed
				$syslog_timestamp,
				$syslog_reporting_system,
				$syslog_service,
				@field_1, 					# Holds first field plus syslog header information
				@fields;					# Holds all service fields

				# Process the log line by line.  Log is not read into memory to prevent swapping huge logs.
				$logfile = $log;
				if( -f $logfile) 
				{ 
					open(LOG, "$logfile") or die("Could not open log $logfile\n");
					$Status{"log $who_am_i"} = "Processing: $logfile";
					foreach $line (<LOG>)
					{
						chomp($line);
						@fields = split(/,/, $line);
						
						$_ = $line;
						if (/^(\S+)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\d{4}).{1,2}([a-zA-Z0-9._]+)[^a-zA-Z]*([a-zA-Z_\/]+)/)
						{
							$month=$2;
							$day=$3;
							$hour=$4;
							$minute=$5;
							$second=$6;
							$timezone=$7;
							$year=$8;
							$syslog_reporting_system=$9;
							$syslog_service=$10;
						}
						if (/^(\S+) - - \[(\d+)\/(\S+)\/(\d+):(\d+):(\d+):(\d+) (\S+)\]/)
						{
							$month=$3;
							$day=$2;
							$hour=$5;
							$minute=$6;
							$second=$7;
							$timezone=$8;
							$year=$4;
							$syslog_reporting_system="WebServer";
							$syslog_service="http";
						}				
						if (/^\[(\S{3})\s\S{3}\s\d{1,2}\s\d{2}:\d{2}\d{2}\s\d{4}\]/)
						{
							$month=$2;
							if($1 eq "Sun") { $day=1; }
							if($1 eq "Mon") { $day=2; }
							if($1 eq "Tue") { $day=3; }
							if($1 eq "Wed") { $day=4; }
							if($1 eq "Thu") { $day=5; }
							if($1 eq "Fri") { $day=6; }
							if($1 eq "Sat") { $day=7; }
							$hour=$4;
							$minute=$5;
							$second=$6;
							$timezone=0;
							$year=$7;
							$syslog_reporting_system="Apache";
							$syslog_service="ApacheErrorLog";
						}
						if (/^(\d{4})\.(\d{1,2})\.(\d{1,2})\s(\d+):(\d+):(\d+)\s-\s(\S+)\]/)
						{
							$month=$2;
							$day=$3;
							$hour=$4;
							$minute=$5;
							$second=$6;
							$timezone=0;
							$year=$1;
							$syslog_reporting_system=$7;
							$syslog_service="DansGuardian";
						}
						if (/^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+([a-zA-Z0-9._]+)/)
						{
							$month=$1;
							$day=$2;
							$hour=$3;
							$minute=$4;
							$second=$5;
							$timezone=0;
							my $localyear, $localmonth;
							$localyear = ((localtime(time))[5]) + 1900;
							$localmonth = ((localtime(time))[4]) + 1;
							if($month > $localmonth) 
							{ 
								$year = $localyear - 1; 
							}
							else
							{
								$year = $localyear;
							}
							$syslog_reporting_system=$6;
							$syslog_service=$7;
						}
						
							#		print "$1 $2 $3 $4 $5 $6 $7 $8 $9 $10\n";
						if($year > 1990 && $year < 2015)
						{		
							$syslog_timestamp=&timestring_to_unix("$month/$day/$year","$hour:$minute:$second");
						}
						else
						{
							$syslog_timestamp = 0;
							$syslog_reporting_system = 'DAD';
							$syslog_service = 'LogParser';
						}
						&record_event($syslog_reporting_system, $syslog_service, $syslog_timestamp, $syslog_timestamp, $line);
					}
					close(LOG);
					&move_log_processed($logfile);
				}
			}
		}
		$Total_Sleep=0;
		$Status{"log $who_am_i"} = "Waiting";
	}
print "\t$who_am_i Exited\n";
$Status{"log $who_am_i"} = "Dead.";
delete $Processing{$system};
return;
}

sub timestring_to_unix
{
	my $d = shift;
	my $t = shift;
	my %months = (
		'Jan', 0,
		'Feb', 1,
		'Mar', 2,
		'Apr', 3,
		'May', 4,
		'Jun', 5,
		'Jul', 6,
		'Aug', 7,
		'Sep', 8,
		'Oct', 9,
		'Nov', 10,
		'Dec', 11);
	my $time;
	my @a;
	@a = split /\//, $d;
	$a[0] = $months{$a[0]};
	@t = split /:/, $t;
	$time = timelocal($t[2], $t[1], $t[0], $a[1], $a[0], $a[2]);
	if($DEBUG)
	{
		print "	$d $t = timelocal($t[2], $t[1], $t[0], $a[1], $a[0], $a[2]) = $time\n";
	}
	return $time;
}



##################################################
#
# Get_Unprocessed_Log_Paths - Identifies files not yet logged
# Takes as an argument the filepath where logs are stored
#
##################################################
sub Get_Unprocessed_Log_Paths
{
	my $path = shift;
	my $depth = shift;
	my $file, @unprocessed;
	my @entries;
	@entries = ();
	@unprocessed = ();
	my @_file_array;
	
	opendir DIR, "$path";
	@entries = grep !/^\..*$/, readdir DIR;
	closedir DIR;
	if(!$depth) { $depth = 0; }
	if($Output){print "Processing $path $depth\n";}
	foreach $file (@entries)
	{
		$file = "$path/$file";
		if( -d $file) { &Get_Unprocessed_Log_Paths($file, $depth+1) };
		if( -f $file) { $_file_array[++$#_file_array] = $file; }
	}
	if($depth == 0) # Only true if we're the first iteration and not a recursion
	{
		foreach $file (@_file_array)
		{
				$unprocessed[++$#unprocessed] = $file;
		}
	}
	undef(@entries);
	undef(@_file_array);
	return @unprocessed
}

