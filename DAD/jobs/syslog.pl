#!c:/perl/bin/perl.exe
use IO::Socket;
use Time::Local;
use POSIX;

my $buf;
my $Filename, $RotateTime = 0;

$LOGSTAGING="C:/dad/jobs/LogStaging";
$LOGPROCESSING="C:/dad/jobs/LogsToProcess";

$sock = IO::Socket::INET->new(LocalPort => '514', Proto => 'udp')||die("Socket: $@");

do{
	$sock->recv($buf, 1540);
	my ($port, $ipaddr) = sockaddr_in($sock->peername);
	@dq = unpack("C4", $ipaddr);
	$address = join(".", @dq);
	$buf =~ s/^<[0-9]+>//;
	logit($address, $buf);
}while(1);

sub logit{
	my $host = shift;
	my $message = shift;
	&RotateLog;
	print "h:$host m:$message\n";
}

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
		$RotateTime += 600;
	}
}