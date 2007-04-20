#!C:/Perl/bin/perl.exe
#
#   This file is a part of the DAD Log Aggregation and Analysis tool
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

# If the drive mapping for logs changes, this line is the only thing that should need to be adjusted.  Every file
# in this directory and below will be processed as a log file.  You have been warned. :^)
my $PENDING_LOG_LOCATION="C:/DAD/jobs/LogsToProcess";
my @_file_array;
my @LineMatches, %FieldCutters;

use Time::Local;

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
	if($DEBUG)
	{
		print "	$d $t = timelocal($t[2], $t[1], $t[0], $a[1], $a[0], $a[2])\n";
	}
	$time = timelocal($t[2], $t[1], $t[0], $a[1], $a[0], $a[2]);
	return $time;
}

# External modules:
use DBI;
$DEBUG=0;
# Module globals
my	$dsn, 						# Database connection
	$dbh,						# Database handle
	@logfiles,					# Array of logs requiring processing
	$log,
	%Service_IDs,				# Holds known and used Service IDs from the database
	%System_IDs;				# Holds known and used System IDs from the database

# Open connection to the database:
#Read in and evaluate the configuration values
open(FILE,"../dbconfig.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);
$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to process syslogs.\n");

# Grab the log file names
print "Grabbing log paths\n";
@logfiles = &Get_Unprocessed_Log_Paths($PENDING_LOG_LOCATION);
print "Getting carving rules";
&Get_Rules();
print "Processing logs:\n";
foreach $log (@logfiles)
{
	print "\tProcessing: $log\n";
	&process_syslog($log);
}
print "Done!\n";

##################################################
#
# Get_Rules()
# Imports carving rules and matching rules from the database for log carving
#
##################################################
sub Get_Rules
{
	my $SQL = "SELECT match_rule, carve_rule FROM dad_adm_carvers";
	my $result_set, @row;
	my $i;
	
	$i = 0;
	@result_set = &SQL_Query($SQL);
	while(@row = shift(@$result_set))
	{
		$LineMatches[$i] = $row[0];
		$FieldCutters{"$row[0]"} = $row[1];
	}
}

##################################################
#
# Get_Unprocessed_Log_Paths - Identifies files not yet logged
# Takes as an argument the filepath where logs are stored
#
##################################################
sub Get_Unprocessed_Log_Paths
{
	my $path = $_[0];
	my $depth = $_[1];
	my $file, @unprocessed, @row;
	my @entries = glob("$path/*");
	if(!$depth) { $depth = 0; }
	print "Processing $path $depth\n";
	foreach $file (@entries)
	{
		if( -d $file) { &Get_Unprocessed_Log_Paths($file, $depth+1) };
		if( -f $file) { $_file_array[++$#_file_array] = $file; }
	}
	if($depth == 0) # Only true if we're the first iteration and not a recursion
	{
		foreach $file (@_file_array)
		{
			@row = &SQL_Query("SELECT CIS_Imported_ID FROM dad_sys_cis_imported WHERE Log_Name = '$file'");
			if(!(@row)) # Not processed
			{
				$unprocessed[++$#unprocessed] = $file;
			}
		}
	}
	return @unprocessed
}

sub mark_log_processed
{
	my $logfile = $_[0];
	&SQL_Insert("INSERT INTO dad_sys_cis_imported (Log_Name) VALUES ('$logfile')");
}

##################################################
#
# process_syslog - Processes the passed in syslog
# Takes as an argument the filepath for a syslog to import
#
##################################################
sub process_syslog
{
my	$line, 						# Temp var for lines being processed
	$logfile, 					# Path to log file being processed
	$syslog_timestamp,
	$syslog_reporting_system,
	$syslog_service,
	@field_1, 					# Holds first field plus syslog header information
	@fields;					# Holds all service fields

	# Process the log line by line.  Log is not read into memory to prevent swapping huge logs.
	$logfile = $_[0];
	open(LOG, "$logfile") || die("Could not open '$logfile' for reading.\n");
	foreach $line (<LOG>)
	{
		chomp($line);
		$line =~ s/(['"`])/\\\1/g;		# Escape quotes
		@fields = split(/,/, $line);
		@field_1 = split(/ +/, $fields[0]);
		$syslog_timestamp=&timestring_to_unix("$field_1[0]/$field_1[1]/[0-9]{4}",$field_1[2]);
		$syslog_reporting_system = $field_1[3];
		$syslog_service = $field_1[4];
		$syslog_service =~ s/[^a-zA-Z\- ]//g;
		$fields[0] = $field_1[5]; #Moves the domain ID from the @field_1 set to position zero of @fields.
		&record_event($syslog_timestamp, $syslog_reporting_system, $syslog_service, @fields);
	}
	close(LOG);
	&mark_log_processed($logfile);
}

##################################################
#
# record_event - Push the event into the database
# Takes as arguments the timestamp, reporting system, service followed by an array of fields
# Maintains the %System_IDs and %Service_IDs hashes
#
##################################################
sub record_event
{
	my $time, $system, $service, @values, @row, $Service_ID, $System_ID;
	($time, $system, $service, @values) = @_;
	
	# See if the service is known.  If not, get it from the database or create a new ID:
	if(! $Service_IDs{"$service"})
	{
		@row = &SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
		my $rows_returned = @row;
		if($rows_returned < 1)
		{
			&SQL_Insert("INSERT INTO dad_sys_services (Service_Name) VALUES ('$service')");
			@row = &SQL_Query("SELECT Service_ID, Service_Name FROM dad_sys_services WHERE Service_Name = '$service'");
			$rows_returned = @row;
			if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (service)!\n"); }
		}
		$Service_IDs{"$service"} = $row[0];
	}

	# See if the system is known.  If not, get it from the database or create a new ID:
	if(! $System_IDs{"$system"})
	{
		@row = &SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
		my $rows_returned = @row;
		if($rows_returned < 1)
		{
			&SQL_Insert("INSERT INTO dad_sys_systems (System_Name) VALUES ('$system')");
			@row = &SQL_Query("SELECT System_ID, System_Name FROM dad_sys_systems WHERE System_Name = '$system'");
			$rows_returned = @row;
			if($rows_returned < 1) { die ("Insert must have failed, I couldn't select the new data (system)!\n"); }
		}
		$System_IDs{"$system"} = $row[0];
	}
	
	# Now insert a new event with the correct system and service IDs
	&SQL_Insert("INSERT INTO dad_sys_events (SystemID, TimeWritten, ServiceID, ".
		"Field_0, Field_1, Field_2, Field_3, Field_4, Field_5, Field_6, Field_7, Field_9, Field_10) ".
		"VALUES (". $System_IDs{"$system"} .", ".
		"'$time', ".
		$Service_IDs{"$service"}.", ".
		"'$values[0]', '$values[1]', '$values[2]', '$values[3]', '$values[4]', ".
		"'0', '$values[6]', '$values[5]', '$values[7]', '$values[8]')");
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
	my @result_set = $query->fetchrow_array();
	$query->finish();
	return @result_set;
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
	if($DEBUG){print "$SQL\n"; return;}
	my $query = $dbh->prepare($SQL);
	$query -> execute();
	$query->finish();
}

##################################################
#
# process_access_log - Processes the passed in web access log
# Takes as an argument the filepath for a web access log to import
#
##################################################
sub process_access_log
{
my	$line, 						# Temp var for lines being processed
	$logfile, 					# Path to log file being processed
	$syslog_timestamp,
	$syslog_reporting_system,
	$syslog_service,
	@field_1, 					# Holds first field plus syslog header information
	@fields;					# Holds all service fields

	# Process the log line by line.  Log is not read into memory to prevent swapping huge logs.
	$logfile = $_[0];
	open(LOG, "$logfile") || die("Could not open '$logfile' for reading.\n");
	foreach $line (<LOG>)
	{
		chomp($line);
		$line =~ s/['"`]/~/g;
		@fields = split(/,/, $line);
		@field_1 = split(/ +/, $fields[0]);
		$syslog_timestamp = "$field_1[0]/$field_1[1]/$field_1[2]";
		$syslog_reporting_system = $field_1[3];
		$syslog_service = $field_1[4];
		$syslog_service =~ s/[^a-zA-Z\- ]//g;
		$fields[0] = $field_1[5]; #Moves the domain ID from the @field_1 set to position zero of @fields.
		&record_event($syslog_timestamp, $syslog_reporting_system, $syslog_service, @fields);
	}
	close(LOG);
	&mark_log_processed($logfile);
}
