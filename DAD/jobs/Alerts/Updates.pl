use LWP::Simple;
$page = get "http://www.cyber-defense.org/DAD_Version";
chomp($page);
open(FILE, "../../DAD_Version") or die("Version file missing.");
@local_file = <FILE>;
$lversion = $local_file[0];
close(FILE);
if($page > $lversion)
{
	system("copy ..\\..\\web\\html\\images\\Updates.jpg ..\\..\\web\\html\\images\\UStatus.jpg");
}
else
{
	system("copy ..\\..\\web\\html\\images\\Blank.jpg ..\\..\\web\\html\\images\\UStatus.jpg");
}