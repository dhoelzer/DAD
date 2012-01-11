#!C:/Perl/bin/perl.exe
#
# Automatic log parser for CIS
#
#

# If the drive mapping for logs changes, this line is the only thing that should need to be adjusted.  Every file
# in this directory and below will be processed as a log file.  You have been warned. :^)
use DBI;
use File::Copy;

# External modules:
$DEBUG=0;
$Output=1;
if($ARGV[0]){$Output=0;}
# Module globals
my	$dsn, 						# Database connection
	$dbh,						# Database handle
	@logfiles,					# Array of logs requiring processing
	$log,
	%Service_IDs,				# Holds known and used Service IDs from the database
	%System_IDs;				# Holds known and used System IDs from the database

open(FILE,"Aggregator.ph") or exit(2);
foreach (<FILE>) { eval(); }
close(FILE);

# Open connection to the database:
$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=DAD";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD") or exit(3);

# Grab the log file names
if($Output){print "Grabbing log paths\n";}
@logfiles = &Get_Unprocessed_Log_Paths($LOG_SNARF_FROM_LOCATION);
if($Output){print "Processing logs:\n";}
foreach $log (@logfiles)
{
	if($Output){print "\tProcessing: $log\n";}
	$newname = $log;
	$newname =~ s/.*\/(.*)/$1/;
	copy($log, $LOG_STAGING_LOCATION."/$newname") or die("Could not copy log $log!\n");
	rename($LOG_STAGING_LOCATION."/$newname", $LOG_LOCATION."/$newname") or die("Could not move processed log $newname!\n");
}

if($Output){print "Done!\n";}


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
	if($Output){print "Processing $path $depth\n";}
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
				if($Output){print "\tNeed to process $file\n"};
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
	my $result;
	#print "$SQL\n";
	$dbh->do($SQL) or die;
	$result = $dbh->{ q{mysql_insertid}};
	return $result;
	
}

