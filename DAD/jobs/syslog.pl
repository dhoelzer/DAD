#!c:/perl/bin/perl.exe
use IO::Socket;

$sock = IO::Socket::INET->new(LocalPort => '514', Proto => 'udp')||die("Socket: $@");

my $buf;
do{
	$sock->recv($buf, 1540);
	my ($port, $ipaddr) = sockaddr_in($sock->peername);
	logit($ipaddr, $buf);
}while(1);

sub logit{
	my $host = shift;
	my $message = shift;
}