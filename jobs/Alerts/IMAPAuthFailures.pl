#!/usr/bin/perl
# Alert on imap logon failures.


require "../Reports/Reports.pm";
#Read in and evaluate the configuration values

$LastChecked = $ARGV[0];
$Severity = 2;
$AlertDescription = "IMAP Authentication Failures";
$result_ref = &GetEventsByStringsPosition($LastChecked, "imap", 15);
$num_results = @$result_ref;
print "results: $num_results\n";

while($arow = shift(@$result_ref))
	{
		@row = @$arow;
		print "\t--@row--\n";
		$server = $row[9];
		$user = $row[38];
		$failures{"$user on $server"} = 1;
	}
foreach(keys %failures)
{
	&ManualAlert($AlertDescription . " - $_", $Severity);	
}


