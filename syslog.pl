#!/usr/bin/perl
use IO::Socket;
use Time::Local;
use POSIX;

# UDP syslog collector: listens on port 514, strips the RFC3164 priority prefix, and
# appends "<source-ip> <message>" to a staging file that import_syslog.rb consumes.
#
# Run as a long-lived foreground process. Port 514 is privileged, so this needs root
# or an equivalent capability. Files rotate into LogsToProcess once a minute, which
# is what makes them visible to the importer.
my $buf;
my $Filename, $RotateTime = 0;
my $DEBUG = 0;

$LOGSTAGING="/var/DAD/Logs/LogStaging";
$LOGPROCESSING="/var/DAD/Logs/LogsToProcess";

$sock = IO::Socket::INET->new(LocalPort => '514', Proto => 'udp')||die("Socket: $@");

do{
	$sock->recv($buf, 1540);
	my ($port, $ipaddr) = sockaddr_in($sock->peername);
	@dq = unpack("C4", $ipaddr);
	$address = join(".", @dq);
	$buf =~ s/^<[0-9]+>//;
	logit($address, $buf);
}while(1);

# Appends one received message to the current staging file.
#
# Takes the source address and the message body. Also echoes to stdout when $DEBUG
# is set. Calls RotateLog on every message, so rotation is driven by incoming
# traffic rather than a timer: with no traffic the open file is never moved.
sub logit{
	my $host = shift;
	my $message = shift;
	&RotateLog;
	chomp($message);
	print LOG "$host $message\n";
	if($DEBUG) { print "$host $message\n" }
}

# Starts a new staging file every 60 seconds, moving the previous one from
# LogStaging into LogsToProcess for the importer to pick up.
#
# Only acts when the current time has passed $RotateTime, which is set to
# "now + 60" each time it fires. The first call opens a file without moving
# anything, since there is nothing to rotate yet.
sub RotateLog
{
	if(mktime(localtime()) > $RotateTime)
	{
		if($RotateTime > 0)
		{
			close(LOG);
			rename "$LOGSTAGING/$Filename", "$LOGPROCESSING/$Filename";
		}
		$RotateTime = mktime(localtime());
		$Filename = "syslog.$RotateTime";
		open(LOG, ">$LOGSTAGING/$Filename");
		$RotateTime += 60;
	}
}