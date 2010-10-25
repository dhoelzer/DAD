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
use GD::Graph::lines;

#Read in and evaluate the configuration values
open(FILE,"Aggregator.ph") or die "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
	or die ("Could not connect to DB server to import the list of servers to poll.\n");

&_build_stats();


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
		&_get_aggregate_system_stat_data($system,\%Log_Size,\%Inserted, \%ALog_Size, \%AInserted, "Security", $Stat_Time_Period);
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

	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
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
