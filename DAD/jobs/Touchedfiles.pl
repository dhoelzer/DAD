#use strict;
#package dump_renno;

use dbi;

my $db  = DBI->connect( 'DBI:mysql:database=DAD;host=ussrv124a;port=3306', 'root', 'All4Fun' );


my @cols;
my $dad_sys_events_id;
my $file_handle;
my $line;
my $SQL;
my $stmt;



$SQL = q{
    SELECT DISTINCT
      from_unixtime(timegenerated),
      field_10,
      field_2
    FROM dad_sys_events
    WHERE
      (
        (
          (
            idxID_Code like } . my_quote(q{560 TOUCHED FILEPATH HERE%},'l') . q{
            OR idxID_Code like } . my_quote(q{560 TOUCHED FILEPATH HERE%},'l') . q{
             OR idxID_Code like } . my_quote(q{560 TOUCHED FILEPATH HERE%},'l') . q{
          )
          AND
          (
            field_25 = 'EXTENSION'
            OR field_2 = } . my_quote(q{EXPLICIT FILE PATH AND FILE HERE}) . q{
            OR field_2 = } . my_quote(q{EXPLICIT FILE PATH AND FILE HERE}) . q{
            OR field_2 = } . my_quote(q{EXPLICIT FILE PATH AND FILE HERE}) . q{
          )
        )
        OR
        (
          idxID_Code = } . my_quote(q{560 EXPLICIT FILE PATH AND FILE HERE}) . q{
          OR idxID_Code = } . my_quote(q{560 EXPLICIT FILE PATH AND FILE HERE}) . q{
        )
      )
};
$SQL .= " AND TimeWritten > $LastRun";
#print "$SQL\n";
$stmt = $db->prepare($SQL);
print $DBI::err if $DBI::err;

$stmt->execute();
$stmt->bind_columns( \$cols[0], \$cols[1], \$cols[2] );

## OPEN FILE HANDLE here so that the log file is not locked open the whole time the query is running.
$file_handle = open_log( 'C:/DAD/TouchedFileLog',2 ) or die 'Can\'t open log file!!!';

while( $stmt->fetchrow_arrayref ){
    $line .= "$_\t" foreach @cols;
    chop $line;
    print $file_handle "$line\n";
    undef $line;
}
$stmt->finish;
$db->disconnect;
close $file_handle;
flock($file_handle,8);




####################
## $file_handle = open_log( $path[,$logtype][,$separator_type] );
##    $path    = full path to log, including log name
##    $logtype = what type of logging
##             1 - (default) timestamp added to end of given log filename (inserted before file extention, if any)
##             2 - append to given log filename
##             3 - overwrite given log filename
##
    sub open_log{
        my $path    = shift;
        my $logtype = shift || 1;
        my $open_attempts = 0;
        my @path;
        $path=~s|\\|\/|g;

        if( $logtype == 1 ){
            ## timestamp will be inserted into filename
            @path = $path=~/(.*)\/(.*?)[.]{0,1}([^.\/]*)$/g;
            splice @path,1,1 if $path[1] eq '';       #if there is no extention on the file, the filename ends up one element higher than it should
            @_ = localtime(time);
            $_[0] = '0' . $_[0] if length($_[0]) == 1;
            $_[1] = '0' . $_[1] if length($_[1]) == 1;
            $_[2] = '0' . $_[2] if length($_[2]) == 1;
            $_[3] = '0' . $_[3] if length($_[3]) == 1;
            $_[4]++;
            $_[4] = '0' . $_[4] if length($_[4]) == 1;
            $_[5] = $_[5]+1900;
            $path = "$path[0]\/$path[1]-$_[4]$_[3]$_[5]$_[2]$_[1].log";
            until(open(LOG,">$path")){
                $open_attempts++;
                last if $open_attempts == 20;
                print "trying to open again\n";
                sleep 1;
            }
            if( $open_attempts == 20 ){
                return 0;
            }else{
                flock(LOG,2);
                return LOG;
            }
        }elsif( $logtype == 2 ){
            ## will append to given filename
            until(open(LOG,">>$path")){
                $open_attempts++;
                last if $open_attempts == 20;
                print "trying to open again\n";
                sleep 1;
            }
            if( $open_attempts == 20 ){
                return 0;
            }else{
                flock(LOG,2);
                return LOG;
            }
        }elsif( $logtype == 3 ){
            ## will overwrite given filename
            until(open(LOG,">$path")){
                $open_attempts++;
                last if $open_attempts == 20;
                print "trying to open again\n";
                sleep 1;
            }
            if( $open_attempts == 20 ){
                return 0;
            }else{
                flock(LOG,2);
                return LOG;
            }
        }
    }



####################
## $str2 = my_quote( $str1, $type_of_quote );
##    $str1 = string to be quoted. will return the value with leading and trailing single quote for SQL query
##    $str2 = string returned
##    $type_of_quote = if the value will be used in an "=" or a "LIKE" WHERE statement
##        e = an equals statement ( e.g. "=" )
##        l = a like statment ( e.g. "LIKE" ) - this will quadruple backslashes (MySQL wants that for some reason)
    sub my_quote{
        my $str  = shift;
        my $type = shift || 'e';
        if( lc($type) eq 'e' ){
            return $db->quote($str);
        }elsif( lc($type) eq 'l' ){
            $str = $db->quote($str);
            $str =~ s|\\\\|\\\\\\\\|g;
            return $str;
        }
        return;
    }
