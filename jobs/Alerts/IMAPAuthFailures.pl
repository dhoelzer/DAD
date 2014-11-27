#!/usr/bin/perl
# Alert on imap logon failures.

$MAX_FAILURES = 5;

require "../Reports/Reports.pm";
#Read in and evaluate the configuration values

$LastChecked = $ARGV[0];
$Severity = 2;
$AlertDescription = "IMAP Authentication Failures";
$result_ref = &GetEventsByStringsPosition($LastChecked, "imap", 14, "failure;", 20);
$num_results = @$result_ref;

while($arow = shift(@$result_ref))
	{
		@row = @$arow;
		$line = $row[3];
		@fields = split(/ +/, $line);
		$server = $fields[9];
		$user = $fields[37];
		$failures{"$user on $server"} += 1;
	}
foreach(keys %failures)
{
	if($failures{$_} > $MAX_FAILURES)
	{
		&ManualAlert($AlertDescription . " - $_"." ".$failures{$_}." times.", $Severity);
	}
}

