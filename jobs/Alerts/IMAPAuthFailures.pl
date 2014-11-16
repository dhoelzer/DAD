#!/usr/bin/perl
# Alert on imap logon failures.


require "../Reports/Reports.pm";
#Read in and evaluate the configuration values

$LastChecked = $ARGV[0];
$Severity = 2;
$AlertDescription = "IMAP Authentication Failures";
$results = &GetEventsByStrings($LastChecked, "imap", 14, "auth", 16, "failure;", 20);

if !count($results) { exit; }
foreach($results as $row)
	{
		$server = $row[9];
		$user = $row[38];
		$failures{'$user on $server'} = 1;
	}
foreach(%failures as $key)
{
	&ManualAlert($AlertDescription . " - $key", $Severity);	
}


