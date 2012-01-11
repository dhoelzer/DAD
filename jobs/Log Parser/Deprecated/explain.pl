use YAPE::Regex::Explain;

$regex = $ARGV[0];
print YAPE::Regex::Explain->new($regex)->explain();