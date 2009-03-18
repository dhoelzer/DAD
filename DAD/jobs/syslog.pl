#!c:/perl/bin/perl.exe
use IO::Socket;

# Variables and Constants
my $MAXLEN = 1524;
my ($lsec,$lmin,$lhour,$lmday,$lmon,$lyear,$lwday,$lyday,$lisdst)=localtime(time); $lyear+=1900; $lmon+=1;

# Start Listening on UDP port 514
$sock = IO::Socket::INET->new(LocalPort => '514', Proto => 'udp')||die("Socket: $@");

my $rin = '';
my $buf;
do{
	$sock->recv($buf, $MAXLEN);
	my ($port, $ipaddr) = sockaddr_in($sock->peername);
	my $hn = gethostbyaddr($ipaddr, AF_INET);
	$buf=~/<(\d+)>(.*?):(.*)/;
	my $pri=$1;
	my $head=$2;
	my $msg=$3;
	my $sev=$pri % 8;
	my $fac=($pri-$sev) / 8;
	logsys($fac,$sev,$head,$msg,$hn);
}while(1);

# Logs Syslog messages
sub logsys{
	my $fac=shift; my $sev=shift; my $head=shift; my $msg=shift; my $hn=shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); $year+=1900; $mon++;
	my $pf=""; my $fn=""; my $facdiff="";
	if ($perfacility){$facdiff="-".$fact[$fac];}
	if ($daily){$facdiff.=sprintf "-%04d-%02d-%02d", $year, $mon, $mday;}
	if ($perhost){mkdir("log\\$hn"); $fn=$hn . "\\syslog".$facdiff.".log"; $pf=$hn ."\\";}else{$fn="syslog".$facdiff.".log";}
	my $p=sprintf "[%02d.%02d.%04d, %02d:%02d:%02d, %1d, %1d] %s\n", $mday, $mon, $year, $hour, $min, $sec, $fac, $sev, $msg;
	print $p;
	if (open(WW,">>log\\$fn")){print WW $p;close(WW);}
}