#!/usr/bin/perl
# Alert on imap logon failures.


require "../Reports/Reports.pm";
#Read in and evaluate the configuration values

$LastChecked = $ARGV[0];
$Severity = 2;
$AlertDescription = "IMAP Authentication Failures";
$resultsref = &GetEventsByStrings($LastChecked, "imap", 14, "auth", 16, "failure;", 20);
$num_results = @$results;
print $num_results;

foreach(@$results)
	{
		@row = @$_;
		print "--@row--";
		$server = $row[9];
		$user = $row[38];
		$failures{"$user on $server"} = 1;
	}
foreach(keys %failures)
{
	&ManualAlert($AlertDescription . " - $_", $Severity);	
}


