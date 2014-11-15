#!/usr/bin/perl

# Converted to UNIX systems in 11/2014 because I'm sick of supporting Windows weirdness.

# Scheduler.pl
# DAD
#
# Created by David Hoelzer on 3/17/09.
# Copyright 2009 Enclave Forensics, All rights reserved.

# This Perl script completely replaces the Java scheduler to allow for easier portability.
# This script requires Win32::Process.  A future version of the script will be created for
# UNIX based systems using Proc::Simple, which is broken in Win32 implementations.

require "dbconfig.ph";

use Time::Local;
use DBI;
use POSIX;
use threads;

my %RunningJobs;

&DB_Connect;
while(1)
{
	@PendingJobs = &_get_persistent_jobs;
	foreach(@PendingJobs)
	{
		print "Persistent job restarting:\n";
		&StartJob($_);
	}	
	@PendingJobs = &_get_pending_jobs;
	foreach(@PendingJobs)
	{
		&StartJob($_);
	}
	print "Process list:\n";
	foreach(keys %RunningJobs)
	{
		my $exitcode;
		if($exitcode == $RunningJobs{$_}->is_running())
		{
			print "\t$Descriptions{$_} -> Running\n";
		}
		else
		{
			print "\t$Descriptions{$_} -> Completed - Deleting job\n";
			delete $RunningJobs{$_};
		}
	}
	sleep(60);
}

sub ErrorReport{
                print Win32::FormatMessage( Win32::GetLastError() );
        }
 		
sub StartJob
{
	my $JobID = shift();
	my $ThisProcess;
	
	if($RunningJobs{$JobID})
	{
		my $exitcode;
		$ThisProcess = $RunningJobs{$JobID};
		if($ThisProcess->is_running())
		{
			print "Won't restart $Descriptions{$JobID}, still running.\n";
			return;
		}
		$ThisProcess->join;
	}
	print "Starting $Descriptions{$JobID}\n";
    print "Executing cd $Paths{$JobID} && $Executable{$JobID} $Arguments{$JobID}\n";
    my $thread = threads->new (sub { system("cd ".$Paths{$JobID}." && ".$Executable{$JobID} . " " . $Arguments{$JobID}) } );
	$RunningJobs{$JobID} = $thread;
	my $now = mktime(localtime());
	my $next = $now + $Intervals{$JobID};
	my $SQL = "UPDATE dad_adm_job SET is_running=1, last_ran=$now, next_start=$next WHERE id_dad_adm_job=$JobID";
	&SQL_Insert($SQL);
}
	
sub _get_persistent_jobs
{
	return(&_get_pending_jobs("Persistent"));
}

sub _get_pending_jobs
{
	my	$results_ref,				# Used to hold query responses
	$row,						#Row array reference
	@this_row;					#Current row
	my @TheseJobs;
	
	$PERSIST = (($_[0] eq "Persistent") ? " WHERE persistent=1" : "WHERE persistent=0");
	$results_ref = &SQL_Query("SELECT id_dad_adm_job, descrip, path, package_name, argument_1, next_start, is_running, persistent, min, hour, day, month, last_ran FROM dad_adm_job $PERSIST");
	while($row = shift(@$results_ref) ) 
	{
		@this_row = @$row;
		if(mktime(localtime()) > $this_row[5]) 
		{
			unshift(@TheseJobs, $this_row[0]);
			$Descriptions{$this_row[0]} = $this_row[1];
			$Executable{$this_row[0]} = $this_row[3];
			$Arguments{$this_row[0]} = "$this_row[4] $this_row[12]";
			$Paths{$this_row[0]} = $this_row[2];
			$Intervals{$this_row[0]} = $this_row[8] * 60 + $this_row[9] * 3600 + $this_row[10] * 86400 + ($this_row[11] * 86400 * 30)
		}
	}
	undef $results_ref;
	undef $row;
	return(@TheseJobs);
}

##################################################
#
# DB_Connect - Builds initial connection to database server
#
##################################################
sub DB_Connect
{
	undef $dsn;
	undef $dhb;
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server\n");
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
		&DB_Connect();
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

