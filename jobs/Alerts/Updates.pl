use LWP::Simple;
$page = get "http://www.cyber-defense.org/DAD_Version";
chomp($page);
open(FILE, "../../DAD_Version") or die("Version file missing.");
@local_file = <FILE>;
$lversion = $local_file[0];
close(FILE);
if($page > $lversion)
{
	system("cp ../../web/html/images/Updates.gif ../../web/html/images/UStatus.gif");
}
else
{
	system("copy ../../web/html/images/Blank.gif ../../web/html/images/UStatus.gif");
}